import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

typealias CoworkMLXLoadProgressHandler = @Sendable (String?) -> Void

/// In-process MLX-LM inference on Apple Silicon (Murmura-style, no Python).
actor CoworkMLXNativeRuntime {
    static let shared = CoworkMLXNativeRuntime()

    static let defaultHuggingFaceRepoID = CoworkMLXModelCatalog.defaultRepoID

    private var container: ModelContainer?
    private var loadedRepoID: String?
    private var inFlightLoad: Task<ModelContainer, Error>?
    private var inFlightRepoID: String?
    private var didApplyGPUMemoryHeuristic = false
    private var loadProgressHandler: CoworkMLXLoadProgressHandler?

    enum MLXRuntimeError: LocalizedError {
        case emptyModelID

        var errorDescription: String? {
            switch self {
            case .emptyModelID:
                return "MLX model id is empty (expected a Hugging Face repo id, e.g. mlx-community/Qwen3-4B-4bit)."
            }
        }
    }

    func unload() async {
        inFlightLoad?.cancel()
        inFlightLoad = nil
        inFlightRepoID = nil
        container = nil
        loadedRepoID = nil
        didApplyGPUMemoryHeuristic = false
        Memory.clearCache()
    }

    func prepareForLoad(repoID: String) async {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if loadedRepoID != trimmed {
            await unload()
        }
    }

    func complete(
        system: String,
        user: String,
        numCtx: Int,
        modelID: String,
        maxTokens: Int? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw MLXRuntimeError.emptyModelID }

        let c = try await ensureContainer(repoID: trimmedID)
        var parameters = Self.chatGenerateParameters(modelID: trimmedID)
        parameters.maxKVSize = max(2048, numCtx)
        parameters.maxTokens = maxTokens

        let session = ChatSession(
            c,
            instructions: system,
            generateParameters: parameters
        )
        do {
            let text = try await session.respond(to: user)
            Memory.clearCache()
            return text
        } catch {
            Memory.clearCache()
            throw error
        }
    }

    static func isRecoverableWeightMappingError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        return message.contains("weight not found")
            || (message.contains("key ") && message.contains(" not found"))
    }

    private static func isMissingWeightKeyError(_ error: Error) -> Bool {
        isRecoverableWeightMappingError(error)
    }

    private static func resolveModelConfiguration(repoID: String, forceRemoteRepair: Bool) async -> ModelConfiguration {
        guard !forceRemoteRepair else {
            return ModelConfiguration(id: repoID, defaultPrompt: "")
        }
        if let dir = await CoworkMLXHubSnapshot.localSnapshotDirectory(repoID: repoID) {
            return ModelConfiguration(directory: dir, defaultPrompt: "")
        }
        return ModelConfiguration(id: repoID, defaultPrompt: "")
    }

    private func reportProgress(_ message: String?) {
        loadProgressHandler?(message)
    }

    private static func loadChatContainer(
        repoID: String,
        forceRemoteRepair: Bool,
        progress: CoworkMLXLoadProgressHandler?
    ) async throws -> ModelContainer {
        let configuration = await resolveModelConfiguration(repoID: repoID, forceRemoteRepair: forceRemoteRepair)
        let downloader = CoworkMLXHubFilewiseDownloader()
        var resolved = try await resolve(
            configuration: configuration,
            from: downloader,
            useLatest: forceRemoteRepair,
            progressHandler: { prog in
                let pct = Int(prog.fractionCompleted * 100)
                progress?("Downloading model… \(pct)%")
            }
        )
        resolved = try applyingLocalCompatibilityPatches(
            to: resolved,
            repoID: repoID
        )
        progress?("Loading model weights…")
        let localConfiguration = ModelConfiguration(
            directory: resolved.modelDirectory,
            tokenizerSource: .directory(resolved.tokenizerDirectory),
            defaultPrompt: resolved.defaultPrompt,
            extraEOSTokens: resolved.extraEOSTokens,
            eosTokenIds: resolved.eosTokenIds,
            toolCallFormat: resolved.toolCallFormat
        )
        return try await loadModelContainer(
            from: downloader,
            using: #huggingFaceTokenizerLoader(),
            configuration: localConfiguration,
            useLatest: forceRemoteRepair
        )
    }

    private func applyGPUMemoryHeuristicIfNeeded() {
        guard !didApplyGPUMemoryHeuristic else { return }
        didApplyGPUMemoryHeuristic = true
        if let recommended = GPU.maxRecommendedWorkingSetBytes() {
            let limit = Int(Double(recommended) * 0.75)
            Memory.cacheLimit = limit
        }
    }

    private func ensureContainer(repoID: String) async throws -> ModelContainer {
        if loadedRepoID == repoID, let container {
            return container
        }

        if inFlightRepoID == repoID, let inFlightLoad {
            let loaded = try await inFlightLoad.value
            container = loaded
            loadedRepoID = repoID
            applyGPUMemoryHeuristicIfNeeded()
            return loaded
        }

        if let inFlightLoad {
            inFlightLoad.cancel()
        }
        inFlightLoad = nil
        inFlightRepoID = nil
        container = nil
        loadedRepoID = nil
        Memory.clearCache()

        reportProgress("Preparing model…")

        let progress = loadProgressHandler
        let loadTask = Task {
            try await Self.loadChatContainer(repoID: repoID, forceRemoteRepair: false, progress: progress)
        }
        inFlightLoad = loadTask
        inFlightRepoID = repoID
        defer {
            reportProgress(nil)
            inFlightLoad = nil
            inFlightRepoID = nil
        }

        do {
            let loaded = try await loadTask.value
            try Task.checkCancellation()
            container = loaded
            loadedRepoID = repoID
            applyGPUMemoryHeuristicIfNeeded()
            return loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard Self.isMissingWeightKeyError(error) else {
                throw error
            }
            let repairTask = Task {
                try await Self.loadChatContainer(repoID: repoID, forceRemoteRepair: true, progress: progress)
            }
            inFlightLoad = repairTask
            let loaded = try await repairTask.value
            try Task.checkCancellation()
            container = loaded
            loadedRepoID = repoID
            applyGPUMemoryHeuristicIfNeeded()
            return loaded
        }
    }

    private static func applyingLocalCompatibilityPatches(
        to resolved: ResolvedModelConfiguration,
        repoID: String
    ) throws -> ResolvedModelConfiguration {
        guard repoID.localizedCaseInsensitiveContains("qwen3.5"),
              qwen35WeightsOmitLMHead(in: resolved.modelDirectory)
        else {
            return resolved
        }

        let configURL = resolved.modelDirectory.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var textConfig = root["text_config"] as? [String: Any],
              (textConfig["tie_word_embeddings"] as? Bool) == false
        else {
            return resolved
        }

        textConfig["tie_word_embeddings"] = true
        root["text_config"] = textConfig
        let patchedConfig = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )

        let overlay = FileManager.default.temporaryDirectory
            .appendingPathComponent("citadel-mlx-overlays", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try createOverlaySnapshot(
            from: resolved.modelDirectory,
            to: overlay,
            patchedConfig: patchedConfig
        )

        let tokenizerDirectory =
            resolved.tokenizerDirectory.standardizedFileURL == resolved.modelDirectory.standardizedFileURL
            ? overlay
            : resolved.tokenizerDirectory

        return ResolvedModelConfiguration(
            modelDirectory: overlay,
            tokenizerDirectory: tokenizerDirectory,
            name: resolved.name,
            defaultPrompt: resolved.defaultPrompt,
            extraEOSTokens: resolved.extraEOSTokens,
            eosTokenIds: resolved.eosTokenIds,
            toolCallFormat: resolved.toolCallFormat
        )
    }

    private static func qwen35WeightsOmitLMHead(in directory: URL) -> Bool {
        let indexURL = directory.appendingPathComponent("model.safetensors.index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weightMap = root["weight_map"] as? [String: Any]
        else {
            return false
        }
        return !weightMap.keys.contains { key in
            key == "lm_head.weight"
                || key == "language_model.lm_head.weight"
                || key == "model.language_model.lm_head.weight"
        }
    }

    private static func createOverlaySnapshot(
        from source: URL,
        to destination: URL,
        patchedConfig: Data
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let sourceURL as URL in enumerator {
            let relativePath = String(sourceURL.path.dropFirst(source.path.count + 1))
            let targetURL = destination.appendingPathComponent(relativePath)

            if sourceURL.lastPathComponent == "config.json" {
                try fm.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try patchedConfig.write(to: targetURL, options: [.atomic])
                continue
            }

            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let resolved = sourceURL.resolvingSymlinksInPath()
                try? fm.removeItem(at: targetURL)
                try fm.createSymbolicLink(at: targetURL, withDestinationURL: resolved)
            }
        }
    }

    func preloadChatModel(modelID: String, progress: CoworkMLXLoadProgressHandler? = nil) async throws {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MLXRuntimeError.emptyModelID }
        loadProgressHandler = progress
        defer { loadProgressHandler = nil }
        await prepareForLoad(repoID: trimmed)
        _ = try await ensureContainer(repoID: trimmed)
    }

    func streamAssistantChat(
        modelID: String,
        instructions: String?,
        history: [Chat.Message],
        latestUser: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        try Task.checkCancellation()
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw MLXRuntimeError.emptyModelID }

        let c = try await ensureContainer(repoID: trimmedID)
        var parameters = Self.chatGenerateParameters(modelID: trimmedID)
        parameters.maxKVSize = Self.chatContextWindowTokens(for: trimmedID)
        let session = ChatSession(
            c,
            instructions: instructions,
            history: history,
            generateParameters: parameters
        )
        return session.streamResponse(to: latestUser)
    }

    private static func chatGenerateParameters(modelID: String) -> GenerateParameters {
        GenerateParameters(temperature: 0.6, prefillStepSize: 512)
    }

    private static func chatContextWindowTokens(for modelID: String) -> Int {
        8192
    }
}
