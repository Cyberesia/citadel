import Foundation
import Combine
import AppKit

/// Cowork feature state — separate from firewall `AppState`.
@MainActor
final class CoworkState: ObservableObject {
    @Published private(set) var coreStatus: CoworkCoreStatus = .stopped
    @Published private(set) var corePort: Int?
    @Published private(set) var coreError: String?

    @Published var assistants: [CoworkAssistant] = []
    @Published var providers: [CoworkProvider] = []
    @Published var conversations: [CoworkConversation] = []
    @Published var messages: [CoworkMessage] = []
    /// Live stream segments — not @Published; UI refreshes via `streamTick` (throttled) for Murmura-class FPS.
    private(set) var liveStreamSegments: [String: CoworkLiveStreamSegment] = [:]
    /// Reasoning kept after stream end so the card collapses instead of disappearing.
    @Published var archivedThinkingByMsgID: [String: CoworkArchivedThinking] = [:]
    /// Tool calls streamed live over WebSocket, keyed by msg_id (rendered before the persisted message exists).
    @Published var liveToolCalls: [String: [CoworkNormalizedToolCall]] = [:]
    @Published var liveToolOrder: [String] = []
    @Published private(set) var streamTick = 0
    private var lastStreamUIPublish = Date.distantPast
    private var streamUIFlushTask: Task<Void, Never>?

    @Published var selectedAssistantID: String = "cowork"
    @Published var selectedProviderID: String?
    @Published var selectedModelID: String?
    @Published var ollamaChatModels: [CoworkOllamaModelsAPI.OllamaModel] = []
    @Published var ollamaReachable = false
    @Published var isLoadingOllamaModels = false
    @Published var mlxInstalledModels: [CoworkMLXInstalledScanner.InstalledModel] = []
    @Published var availableSkills: [CoworkSkill] = []
    @Published var selectedSkillIDs: Set<String> = []
    @Published var agentPermissionMode: String = "default"
    @Published var slashCommands: [CoworkSlashCommand] = []
    @Published var hasMoreMessages = false
    @Published var workspaceSearchQuery = ""
    @Published var fileChanges: [CoworkFileChange] = []
    @Published var pendingCommands: [String] = []
    @Published var promptText: String = ""
    @Published var workspacePath: String = ""

    @Published var activeConversationID: String?
    @Published var isLoadingCatalog = false
    @Published var isSending = false
    @Published var isStreaming = false
    @Published var activeTurnID: String?
    @Published var statusMessage: String?
    /// Increment to move keyboard focus into the active composer (Murmura-style).
    @Published var composerFocusGeneration = 0
    @Published var mlxRuntimeInstallMessage: String?
    @Published private(set) var isBootstrapComplete = false
    @Published var showProviderSheet = false
    @Published var showProvidersManager = false
    @Published var showMcpSheet = false
    @Published var showModelSwitchSheet = false

    @Published var attachmentPaths: [String] = []
    @Published var composerAttachments: [String] = []
    /// Paths whose text was successfully extracted for the next send (shown on attachment chips).
    @Published var indexedAttachmentPaths: Set<String> = []
    @Published var mcpServers: [CoworkMcpServer] = []
    @Published var mcpAgentConfigs: [CoworkMcpAgentConfigGroup] = []
    @Published var selectedMcpIDs: Set<String> = []

    @Published var activeConversation: CoworkConversation?
    @Published var workspaceEntries: [CoworkFSEntry] = []
    @Published var workspaceRelativePath: String = "."
    @Published var previewItems: [CoworkPreviewItem] = []
    @Published var selectedPreviewID: String?
    @Published var pendingConfirmations: [CoworkConfirmation] = []
    @Published var activeConfirmation: CoworkConfirmation?
    /// Survives `closeConversation()` so Allow/Deny still works after leaving the chat.
    @Published private(set) var confirmationAnchorConversationID: String?

    @Published var lastTokenUsage: CoworkTokenUsage?
    @Published var conversationUsage = CoworkConversationUsageStats()
    @Published var messageSearchQuery = ""
    @Published var messageSearchResults: [CoworkMessage] = []
    @Published var cronJobs: [CoworkCronJob] = []
    @Published var managedAgents: [CoworkManagedAgent] = []
    @Published var isScanningAgents = false
    @Published var checkingAgentIDs: Set<String> = []
    @Published var showKeepHelp = false
    @Published var keepHelpTopicID: String?
    @Published var mcpOAuthServers: [String] = []

    // Remote access + chat platform bridges
    @Published var remoteAccessEnabled = false
    @Published var remoteQRToken: String?
    @Published var isRemoteBusy = false
    @Published var channelPlugins: [CoworkChannelPlugin] = []
    @Published var channelPairings: [CoworkChannelPairing] = []
    @Published var channelUsers: [CoworkChannelUser] = []

    // Teams (multi-agent orchestration)
    @Published var teams: [CoworkTeam] = []
    @Published var activeTeamID: String?
    @Published var activeTeam: CoworkTeam?
    @Published var teamRunState: CoworkTeamRunState?
    @Published var teamSlotMessages: [String: [CoworkMessage]] = [:]
    @Published var isTeamBusy = false
    /// Human-readable label while `isTeamBusy` (create team, open, add member, send task).
    @Published var teamActivityMessage: String?
    /// Cached per-assistant eligibility for team pickers (`team_selectable` from the backend).
    @Published var teamAssistantEligibility: [String: CoworkTeamAssistantEligibility] = [:]
    let voiceScribe = CitadelVoiceScribe()

    private static let persistedProviderIDKey = "cowork.selectedProviderID"
    private static let persistedModelIDKey = "cowork.selectedModelID"
    private static let mcpUserConfiguredKey = "cowork.mcp.userConfigured"
    private static let modelPickerTabKey = "cowork.modelPickerTab"
    private var mlxWarmGeneration = 0

    var isCloudModelSelection: Bool {
        guard let providerID = selectedProviderID else { return false }
        return cloudProviders.contains { $0.id == providerID }
    }

    /// True when cloud is active in memory or was the last persisted home-screen choice.
    var prefersCloudModelSelection: Bool {
        if isCloudModelSelection { return true }
        return persistedPrefersCloudModel()
    }

    private func persistedPrefersCloudModel() -> Bool {
        if UserDefaults.standard.string(forKey: Self.modelPickerTabKey) == CoworkModelPickerTab.cloud.rawValue {
            return true
        }
        guard let providerID = UserDefaults.standard.string(forKey: Self.persistedProviderIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !providerID.isEmpty else {
            return false
        }
        return cloudProviders.contains { $0.id == providerID }
    }

    /// Background MLX warm/sync must not run or overwrite selection while cloud is preferred.
    func shouldDeferLocalMLXActivation() -> Bool {
        prefersCloudModelSelection
    }

    func waitForBootstrapIfNeeded() async {
        if isBootstrapComplete { return }
        for _ in 0..<120 {
            if isBootstrapComplete { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func cancelInFlightMLXWarm() {
        mlxWarmGeneration += 1
        mlxRuntimeInstallMessage = nil
    }

    /// Agent tool/MCP pipeline only when the user enabled MCP or Skills.
    /// Otherwise Prefer Murmura-style direct chat (Ollama `think: true` / cloud HTTP).
    func shouldUseAgentToolPipeline(mcpIDs: [String]? = nil, skillIDs: [String]? = nil) -> Bool {
        guard activeModelSupportsTools else { return false }
        let mcp = mcpIDs ?? effectiveMcpIDs
        let skills = skillIDs ?? effectiveSkillIDs
        return !mcp.isEmpty || !skills.isEmpty
    }

    private func isLocalMLXProvider(_ provider: CoworkProvider) -> Bool {
        let base = provider.baseURL.lowercased()
        return base.contains(":8765") || base.contains("mlx")
    }

    private func conversationUsesMLX(_ conversation: CoworkConversation?) -> Bool {
        guard let ref = conversation?.model,
              let provider = providers.first(where: { $0.id == ref.providerID }) else {
            return false
        }
        return isLocalMLXProvider(provider)
    }

    func markMcpUserConfigured() {
        UserDefaults.standard.set(true, forKey: Self.mcpUserConfiguredKey)
    }

    /// Cloud BYOK without MCP/skills — bypasses CoworkCore ACP agent (required for gpt-5.6-luna and other SOTA models).
    var usesDirectCloudChat: Bool {
        guard !shouldUseAgentToolPipeline() else { return false }
        return isCloudModelSelection || isCloudConversation(activeConversation)
    }

    /// Local Ollama without MCP/skills — Murmura-style `/api/chat` + `think: true` (live reasoning).
    var usesDirectOllamaChat: Bool {
        guard !shouldUseAgentToolPipeline() else { return false }
        guard !usesDirectCloudChat else { return false }
        if conversationUsesMLX(activeConversation) || isLocalMLXModelSelection { return false }
        let provider = activeConversation.flatMap { conv in
            conv.model.flatMap { ref in providers.first { $0.id == ref.providerID } }
        } ?? selectedProvider
        guard let provider else { return false }
        let platform = provider.platform.lowercased()
        let base = provider.baseURL.lowercased()
        if platform == "ollama" { return true }
        if platform == "custom", base.contains("11434") || base.contains("1234") { return true }
        return false
    }

    var supportsImplicitLeadingThinking: Bool {
        let model = (activeConversation?.model?.model ?? resolvedModelID)?.lowercased() ?? ""
        guard !model.isEmpty else { return false }
        return model.contains("qwen3")
            || model.contains("deepseek-r1")
            || model.contains("reasoning")
    }

    private func isCloudConversation(_ conversation: CoworkConversation?) -> Bool {
        guard let providerID = conversation?.model?.providerID else { return false }
        return cloudProviders.contains { $0.id == providerID }
    }

    let lifecycle = CoworkCoreLifecycle()
    private let webSocket = CoworkWebSocketClient()
    private var cancellables = Set<AnyCancellable>()
    private var webSocketHandlersRegistered = false
    var thinkingParsers: [String: CoworkThinkingTagStreamParser] = [:]
    private let streamCoalescer = CoworkStreamDeltaCoalescer()
    /// Murmura-style answer typewriter: pending chars drain into `liveStreamSegments` at 4/7ms.
    private var answerTypewriterQueues: [String: String] = [:]
    private var answerTypewriterTasks: [String: Task<Void, Never>] = [:]

    init() {
        lifecycle.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.coreStatus, on: self)
            .store(in: &cancellables)
        lifecycle.$port
            .receive(on: DispatchQueue.main)
            .assign(to: \.corePort, on: self)
            .store(in: &cancellables)
        lifecycle.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: \.coreError, on: self)
            .store(in: &cancellables)

        registerWebSocketHandlers()

        $isStreaming
            .receive(on: DispatchQueue.main)
            .sink { streaming in
                CitadelDeskCompanionController.shared.syncStreaming(streaming)
            }
            .store(in: &cancellables)

        $coreStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard status == .running else { return }
                Task { await self?.bootstrap() }
            }
            .store(in: &cancellables)

        voiceScribe.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Merge live/final dictation into the composer. `existing` is the pre-dictation base.
    static func appendDictationTranscript(to existing: String, transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing }
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return trimmed }
        return existing + (existing.hasSuffix("\n") ? "" : "\n") + trimmed
    }

    var client: CoworkCoreClient? {
        guard let port = corePort, coreStatus == .running else { return nil }
        return CoworkCoreClient(port: port)
    }

    var selectedProvider: CoworkProvider? {
        if let selectedProviderID {
            return providers.first { $0.id == selectedProviderID }
        }
        return providers.first
    }

    var selectedAssistant: CoworkAssistant? {
        assistants.first { $0.id == selectedAssistantID }
            ?? assistants.first { $0.id == "cowork" }
            ?? assistants.first
    }

    /// Model the home composer will send with (respects cloud vs Ollama vs MLX).
    var resolvedHomeModelID: String? {
        if isCloudModelSelection {
            return selectedModelID
        }
        if preferredLocalBackend == .mlx {
            let stored = preferredMLXRepoID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stored.isEmpty { return stored }
            return mlxInstalledModels.first?.id
        }
        return selectedModelID ?? ollamaChatModels.first?.name
    }

    var hasResolvableModelSelection: Bool {
        resolvedHomeModelID != nil
    }

    func ensureCoreReady() async throws {
        if coreStatus == .running { return }
        startCoreIfNeeded()
        for _ in 0..<60 {
            if coreStatus == .running { return }
            if coreStatus == .failed {
                throw CoworkCoreError.notConnected
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw CoworkCoreError.notConnected
    }

    /// Keeps `selectedProviderID` / `selectedModelID` aligned with the Ollama vs MLX picker.
    func syncLocalBackendSelection() async {
        if shouldDeferLocalMLXActivation() { return }
        guard let model = resolvedHomeModelID else { return }

        if preferredLocalBackend == .mlx {
            let mlxURL = CoworkOllamaModelsAPI.normalizedChatBaseURL(CoworkMLXServerBridge.chatBaseURL())
            if let existing = providers.first(where: {
                CoworkOllamaModelsAPI.normalizedChatBaseURL($0.baseURL) == mlxURL
                    && $0.models.contains(model)
            }) {
                selectedProviderID = existing.id
                selectedModelID = model
                return
            }
            try? await ensureCoreReady()
            do {
                try await activateMLXModel(model)
            } catch {
                statusMessage = L10n.localizeError(
                    CoworkMLXModelLibrary.enrichedLoadErrorMessage(error.localizedDescription)
                )
            }
            return
        }

        selectedModelID = model
        if let existing = providers.first(where: { Self.isOllamaEndpoint($0.baseURL) }) {
            selectedProviderID = existing.id
            if !existing.models.contains(model) {
                await selectOllamaModel(model)
            } else {
                persistModelSelection()
            }
            return
        }
        if ollamaReachable || ollamaChatModels.contains(where: { $0.name == model }) {
            await selectOllamaModel(model)
        }
    }

    func ensureMLXReadyForSend(repoID: String) async throws {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoworkMLXBridgeError.invalidModelID }

        guard await CoworkMLXHubSnapshot.localSnapshotDirectory(repoID: trimmed) != nil else {
            throw CoworkMLXBridgeError.modelNotInstalled
        }

        let mlxURL = CoworkOllamaModelsAPI.normalizedChatBaseURL(CoworkMLXServerBridge.chatBaseURL())
        if await CoworkMLXServerBridge.isRunning,
           selectedModelID == trimmed,
           let providerID = selectedProviderID,
           let provider = providers.first(where: { $0.id == providerID }),
           CoworkOllamaModelsAPI.normalizedChatBaseURL(provider.baseURL) == mlxURL,
           provider.models.contains(trimmed) {
            return
        }
        try await activateMLXModel(trimmed)
    }

    /// Preloads MLX weights when the home screen uses Native MLX.
    func warmMLXChatModelIfNeeded() async {
        await waitForBootstrapIfNeeded()
        guard !shouldDeferLocalMLXActivation() else { return }
        guard preferredLocalBackend == .mlx, let repoID = resolvedHomeModelID else { return }
        guard await CoworkMLXHubSnapshot.localSnapshotDirectory(repoID: repoID) != nil else { return }

        mlxWarmGeneration += 1
        let generation = mlxWarmGeneration
        mlxRuntimeInstallMessage = L10n.mlxWarmingUp
        do {
            try await CoworkMLXServerBridge.startIfNeeded(repoID: repoID) { message in
                guard generation == self.mlxWarmGeneration, !self.shouldDeferLocalMLXActivation() else { return }
                self.mlxRuntimeInstallMessage = message ?? L10n.mlxWarmingUp
            }
            guard generation == mlxWarmGeneration, !shouldDeferLocalMLXActivation() else {
                mlxRuntimeInstallMessage = nil
                return
            }
            mlxRuntimeInstallMessage = nil
        } catch {
            guard generation == mlxWarmGeneration else { return }
            mlxRuntimeInstallMessage = nil
        }
    }

    func startCoreIfNeeded() {
        guard coreStatus == .stopped || coreStatus == .failed else { return }
        Task { await lifecycle.start() }
    }

    func stopCore() {
        webSocket.disconnect(clearHandlers: true)
        webSocketHandlersRegistered = false
        lifecycle.stop()
    }

    private func registerWebSocketHandlers() {
        guard !webSocketHandlersRegistered else { return }
        webSocketHandlersRegistered = true

        webSocket.on(event: "message.stream") { [weak self] data in
            Task { @MainActor in
                guard let message = try? JSONDecoder.cowork.decode(CoworkWSResponseMessage.self, from: data) else { return }
                self?.applyStream(message)
            }
        }
        webSocket.on(event: "confirmation.add") { [weak self] data in
            Task { @MainActor in self?.handleConfirmationEvent(data) }
        }
        webSocket.on(event: "confirmation.update") { [weak self] data in
            Task { @MainActor in self?.handleConfirmationEvent(data) }
        }
        webSocket.on(event: "confirmation.remove") { [weak self] data in
            Task { @MainActor in self?.handleConfirmationRemoved(data) }
        }
        webSocket.on(event: "preview.open") { [weak self] data in
            Task { @MainActor in self?.handlePreviewOpen(data) }
        }
        webSocket.on(event: "turn.completed") { [weak self] _ in
            Task { @MainActor in await self?.onTurnCompleted() }
        }
        webSocket.on(event: "conversation.artifact") { [weak self] _ in
            Task { @MainActor in await self?.refreshWorkspace() }
        }
        webSocket.on(event: "conversation.listChanged") { [weak self] _ in
            Task { @MainActor in await self?.refreshConversations() }
        }
        webSocket.on(event: "fileStream.contentUpdate") { [weak self] _ in
            Task { @MainActor in
                await self?.refreshWorkspace()
                await self?.refreshFileChanges()
            }
        }
        webSocket.on(event: "fileWatch.fileChanged") { [weak self] _ in
            Task { @MainActor in
                await self?.refreshWorkspace()
                await self?.refreshFileChanges()
            }
        }
        webSocket.on(event: "cron.job-created") { [weak self] _ in
            Task { @MainActor in await self?.refreshCronJobs() }
        }
        webSocket.on(event: "cron.job-updated") { [weak self] _ in
            Task { @MainActor in await self?.refreshCronJobs() }
        }
        webSocket.on(event: "cron.job-deleted") { [weak self] _ in
            Task { @MainActor in await self?.refreshCronJobs() }
        }
        webSocket.on(event: "cron.job-run") { [weak self] _ in
            Task { @MainActor in await self?.refreshCronJobs() }
        }

        let teamEvents = [
            "team.agentStatusChanged", "team.agentSpawned", "team.agentRemoved",
            "team.runAccepted", "team.runStarted", "team.runUpdated", "team.runCompleted",
            "team.teammateMessage"
        ]
        for event in teamEvents {
            webSocket.on(event: event) { [weak self] _ in
                Task { @MainActor in await self?.onTeamEvent() }
            }
        }

        for event in ["channel.pairing-requested", "channel.plugin-status-changed", "channel.user-authorized"] {
            webSocket.on(event: event) { [weak self] _ in
                Task { @MainActor in await self?.refreshChannels() }
            }
        }
    }

    func bootstrap() async {
        guard let client else { return }
        isBootstrapComplete = false
        isLoadingCatalog = true
        defer {
            isLoadingCatalog = false
            isBootstrapComplete = true
        }

        registerWebSocketHandlers()
        webSocket.connect(url: client.webSocketURL)

        do {
            async let assistantList = client.listAssistants()
            async let providerList = client.listProviders()
            async let conversationList = client.listConversations()
            async let mcpList = client.listMcpServers()
            assistants = try await assistantList
            assistants.sort { a, b in
                let rank: (CoworkAssistant) -> Int = { assistant in
                    switch assistant.id {
                    case "cowork": return 0
                    case "aionui-assistant": return 1
                    default: return 2
                    }
                }
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
            providers = try await providerList
            await repairProviders()
            await bootstrapDefaultMcpIfNeeded()
            conversations = try await conversationList.items
            mcpServers = try await mcpList
            statusMessage = nil

            restorePersistedModelSelection()
            if selectedProviderID == nil {
                selectedProviderID = providers.first?.id
            }
            // Never clobber a restored Ollama tag (e.g. qwen3.6:27b) with provider.models.first.
            if selectedModelID == nil || selectedModelID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                selectedModelID = providers.first?.models.first
            }
            applyMcpDefaultsForSelectedProvider()
            if !assistants.contains(where: { $0.id == selectedAssistantID }),
               let cowork = assistants.first(where: { $0.id == "cowork" }) {
                selectedAssistantID = cowork.id
            }
            await bootstrapDefaultMcpIfNeeded()
            await refreshMcpAgentConfigs()
            await refreshOllamaModels()
            await refreshSkills()
            await refreshMLXModelsAsync()
            if !shouldDeferLocalMLXActivation() {
                await syncLocalBackendSelection()
            } else {
                persistModelSelection()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshConversations() async {
        guard let client else { return }
        do {
            conversations = try await client.listConversations().items
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openConversation(_ id: String) async {
        activeConversationID = id
        workspaceRelativePath = "."
        previewItems = []
        selectedPreviewID = nil
        await loadConversationDetail(id)
        await loadMessages(for: id)
        await refreshWorkspace()
        await refreshConfirmations()
    }

    func requestComposerFocus() {
        composerFocusGeneration += 1
    }

    func requestModelSwitch() {
        showModelSwitchSheet = true
    }

    var activeModelLabel: String {
        activeModelDisplay.alias
    }

    var activeModelSummary: String {
        activeModelDisplay.summary
    }

    var activeModelProviderLabel: String {
        activeModelDisplay.provider
    }

    var activeModelDisplay: CoworkUserFacing.ModelDisplay {
        if let ref = activeConversation?.model {
            return CoworkUserFacing.modelDisplay(
                providerID: ref.providerID,
                rawModel: ref.model,
                providers: providers
            )
        }

        // Home composer — cloud selection wins over a stale MLX backend preference.
        if isCloudModelSelection, let id = selectedModelID {
            return CoworkUserFacing.modelDisplay(
                providerID: selectedProviderID,
                rawModel: id,
                providers: providers
            )
        }

        if preferredLocalBackend == .mlx {
            let repo = preferredMLXRepoID
            return CoworkUserFacing.modelDisplay(
                providerID: "mlx",
                rawModel: repo,
                providers: providers
            )
        }

        if let id = selectedModelID {
            return CoworkUserFacing.modelDisplay(
                providerID: selectedProviderID,
                rawModel: id,
                providers: providers
            )
        }
        return CoworkUserFacing.ModelDisplay(alias: L10n.noModelSelected, technical: nil, provider: "")
    }

    // MARK: - Tool capability (chat-only vs agent tools)

    var resolvedModelID: String? {
        activeConversation?.model?.model ?? selectedModelID
    }

    var resolvedProviderID: String? {
        activeConversation?.model?.providerID ?? selectedProviderID
    }

    var activeModelSupportsTools: Bool {
        CoworkModelToolSupport.supportsTools(
            modelID: resolvedModelID,
            providerID: resolvedProviderID,
            providers: providers,
            ollamaModels: ollamaChatModels
        )
    }

    /// Native MLX OpenAI shim on :8765 — chat-only by design (no tool schemas).
    var isActiveModelNativeMLX: Bool {
        if inferredModelPickerTab == .mlx { return true }
        if let providerID = resolvedProviderID,
           let provider = providers.first(where: { $0.id == providerID }) {
            let base = provider.baseURL.lowercased()
            if base.contains(":8765") || base.contains("mlx") { return true }
        }
        if let model = resolvedModelID,
           mlxInstalledModels.contains(where: { $0.id == model }) {
            return true
        }
        return false
    }

    var effectiveMcpIDs: [String] {
        guard activeModelSupportsTools else { return [] }
        return Array(curatedMcpSelection())
    }

    private func mcpToolProfile() -> CoworkMcpToolProfile {
        CoworkModelToolSupport.mcpToolProfile(platform: resolvedProviderPlatform() ?? "custom")
    }

    /// Applies Cursor-style MCP curation: schema-safe servers, tool budget, heavy servers excluded by default on cloud.
    func curatedMcpSelection(preferDefaults: Bool = false) -> Set<String> {
        CoworkMcpCurator.curatedIDs(
            servers: mcpServers,
            userSelected: selectedMcpIDs,
            profile: mcpToolProfile(),
            preferDefaults: preferDefaults
        )
    }

    /// Refreshes cached MCP tool lists (when missing) and re-applies curation before send.
    func prepareMcpSelectionForSend() async {
        guard activeModelSupportsTools else { return }
        guard let client else { return }

        let profile = mcpToolProfile()
        guard profile != .localPermissive else { return }

        let candidates = mcpServers.filter { selectedMcpIDs.contains($0.id) && ($0.tools?.isEmpty != false) }
        for server in candidates {
            guard let transport = server.transport else { continue }
            _ = try? await client.testMcpConnection(
                CoworkMcpTestConnectionRequest(id: server.id, name: server.name, transport: transport)
            )
        }
        if !candidates.isEmpty {
            if let refreshed = try? await client.listMcpServers() {
                mcpServers = refreshed
            }
        }

        let before = selectedMcpIDs
        let after = curatedMcpSelection()
        selectedMcpIDs = after
        if let dropped = CoworkMcpCurator.droppedServerSummary(
            servers: mcpServers,
            before: before,
            after: after,
            profile: profile
        ) {
            statusMessage = L10n.mcpCuratedDropNotice(dropped)
        }
    }

    var effectiveSkillIDs: [String] {
        activeModelSupportsTools ? Array(selectedSkillIDs) : []
    }

    var toolsDisabledNotice: String? {
        guard resolvedModelID != nil else { return nil }
        if !activeModelSupportsTools {
            return isActiveModelNativeMLX ? L10n.chatOnlyMLXNotice : L10n.chatOnlyModeNotice
        }
        if !shouldUseAgentToolPipeline() {
            return L10n.chatOnlyEnableToolsNotice
        }
        return nil
    }

    var toolsDisabledNoticeOffersModelSwitch: Bool {
        guard resolvedModelID != nil else { return false }
        return !activeModelSupportsTools
    }

    /// Applies tool-capable or chat-only assistant snapshot so CoworkCore stops wiring tools for plain LLMs.
    func applyToolCapabilityProfile() async {
        guard let client, let conversationID = activeConversationID else { return }
        if availableSkills.isEmpty { await refreshSkills() }

        let assistantID = selectedAssistantID
        let locale = CitadelLocale.current.rawValue

        do {
            if activeModelSupportsTools, shouldUseAgentToolPipeline() {
                let mcp = effectiveMcpIDs
                let skills = effectiveSkillIDs
                let updated = try await client.updateConversation(
                    id: conversationID,
                    CoworkUpdateConversationRequest(
                        assistant: CoworkAssistantRef(
                            id: assistantID,
                            locale: locale,
                            conversationOverrides: CoworkConversationOverrides(
                                model: resolvedModelID,
                                permission: agentPermissionMode,
                                mcpIDs: mcp,
                                skillIDs: skills
                            )
                        ),
                        extra: CoworkConversationExtra(
                            selectedMcpServerIDs: mcp,
                            skillIDs: skills
                        ),
                        mergeExtra: true
                    )
                )
                activeConversation = updated
            } else {
                let disabledSkills = availableSkills.map(\.name)
                let updated = try await client.updateConversation(
                    id: conversationID,
                    CoworkUpdateConversationRequest(
                        assistant: CoworkAssistantRef(
                            id: assistantID,
                            locale: locale,
                            conversationOverrides: CoworkConversationOverrides(
                                model: resolvedModelID,
                                permission: agentPermissionMode,
                                mcpIDs: [],
                                skillIDs: [],
                                disabledBuiltinSkillIDs: disabledSkills
                            )
                        ),
                        extra: CoworkConversationExtra(
                            selectedMcpServerIDs: [],
                            skillIDs: [],
                            presetContext: L10n.chatOnlyPresetContext,
                            enabledSkills: [],
                            excludeBuiltinSkills: disabledSkills,
                            excludeAutoInjectSkills: disabledSkills
                        ),
                        mergeExtra: true
                    )
                )
                activeConversation = updated
                statusMessage = nil
                try await client.ensureRuntime(conversationID: conversationID)
            }
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    /// Applies chat-only or tool-capable runtime config, then ensures CoworkCore rebuilt the session.
    func prepareConversationRuntimeBeforeSend(conversationID: String) async {
        await applyToolCapabilityProfile()
        try? await client?.ensureRuntime(conversationID: conversationID)
    }

    private func cloudChatHistory(for conversationID: String) -> [CoworkCloudDirectChat.Turn] {
        messages
            .filter { $0.conversationID == conversationID || $0.conversationID == nil }
            .filter { !$0.isTips && !$0.isToolMessage && !$0.isThinking && $0.hidden != true }
            .compactMap { msg -> CoworkCloudDirectChat.Turn? in
                let text = msg.textBody.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let role = msg.isUser ? "user" : "assistant"
                return CoworkCloudDirectChat.Turn(role: role, content: text)
            }
    }

    /// Sends via provider HTTP API (no ACP agent). Used for cloud SOTA models in conversation-only mode.
    func sendViaDirectCloudChat(
        conversationID: String,
        text: String,
        provider: CoworkProvider,
        model: String,
        preStampedUserID: String? = nil
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if preStampedUserID == nil {
            messages.append(CoworkMessage(
                localID: UUID().uuidString,
                conversationID: conversationID,
                position: "right",
                text: trimmed
            ))
        }
        persistDirectChatTranscript(conversationID: conversationID)

        isStreaming = true
        statusMessage = nil
        defer {
            isStreaming = false
            activeTurnID = nil
        }

        let history = cloudChatHistory(for: conversationID).filter { $0.role == "user" || $0.role == "assistant" }
        let prior = history.dropLast()
        let response = try await CoworkCloudDirectChat.complete(
            provider: provider,
            model: model,
            history: Array(prior),
            userMessage: trimmed,
            systemPrompt: L10n.chatOnlyPresetContext
        )

        let assistantID = UUID().uuidString
        messages.append(CoworkMessage(
            localID: assistantID,
            conversationID: conversationID,
            position: "left",
            text: response
        ))
        persistDirectChatTranscript(conversationID: conversationID)
    }

    /// Sends via Ollama `/api/chat` with `think: true` (Murmura path) — live reasoning + answer stream.
    func sendViaDirectOllamaChat(
        conversationID: String,
        text: String,
        provider: CoworkProvider,
        model: String,
        preStampedUserID: String? = nil,
        preStampedUserText: String? = nil
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userVisible = (preStampedUserText ?? trimmed).trimmingCharacters(in: .whitespacesAndNewlines)

        if preStampedUserID == nil {
            messages.append(CoworkMessage(
                localID: UUID().uuidString,
                conversationID: conversationID,
                position: "right",
                text: userVisible
            ))
            persistDirectChatTranscript(conversationID: conversationID)
        } else if trimmed != userVisible,
                  let idx = messages.firstIndex(where: { $0.msgID == preStampedUserID }) {
            // Enrichment added document context — keep bubble label as the typed prompt.
            _ = idx
            persistDirectChatTranscript(conversationID: conversationID)
        } else {
            persistDirectChatTranscript(conversationID: conversationID)
        }

        let msgID = UUID().uuidString
        resetAnswerTypewriter(msgID: msgID)
        streamCoalescer.reset(msgID: msgID)
        thinkingParsers[msgID] = CoworkThinkingTagStreamParser(
            supportsImplicitLeadingThinking: false
        )
        liveStreamSegments[msgID] = CoworkLiveStreamSegment()
        isStreaming = true
        statusMessage = nil
        activeTurnID = msgID

        let history: [(role: String, content: String)] = messages
            .filter { $0.conversationID == conversationID || $0.conversationID == nil }
            .filter { !$0.isTips && !$0.isToolMessage && !$0.isThinking && $0.hidden != true }
            .compactMap { msg in
                let body = msg.textBody.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { return nil }
                return (msg.isUser ? "user" : "assistant", body)
            }
        // Replace last user turn with enriched content for the model, keep UI bubble as typed text.
        var prior = Array(history.dropLast())
        prior.append((role: "user", content: trimmed))

        do {
            try await CoworkOllamaChatStream.streamResponse(
                baseURL: provider.baseURL,
                model: model,
                messages: prior,
                systemPrompt: L10n.chatOnlyPresetContext
            ) { [weak self] delta in
                guard let self else { return }
                // Murmura: coalesce before parser/UI so 27B doesn’t reparse markdown every token.
                self.streamCoalescer.enqueue(
                    msgID: msgID,
                    piece: delta,
                    preferFastFlush: self.shouldPreferFastStreamFlush(msgID: msgID)
                ) { [weak self] merged in
                    self?.applyStreamTextChunk(msgID: msgID, chunk: merged)
                }
            }
        } catch {
            await streamCoalescer.flush(msgID: msgID) { [weak self] merged in
                self?.applyStreamTextChunk(msgID: msgID, chunk: merged)
            }
            finalizeDirectOllamaTurn(msgID: msgID, conversationID: conversationID)
            isStreaming = false
            activeTurnID = nil
            throw error
        }

        await streamCoalescer.flush(msgID: msgID) { [weak self] merged in
            self?.applyStreamTextChunk(msgID: msgID, chunk: merged)
        }
        finalizeDirectOllamaTurn(msgID: msgID, conversationID: conversationID)
        isStreaming = false
        activeTurnID = nil
        requestComposerFocus()
    }

    /// Persist the live segment into `messages` without dropping a reply that only lived in thinking.
    private func finalizeDirectOllamaTurn(msgID: String, conversationID: String) {
        flushAnswerTypewriter(msgID: msgID)

        if var parser = thinkingParsers.removeValue(forKey: msgID) {
            let remainder = parser.flush()
            var segment = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
            if !remainder.thinking.isEmpty { segment.thinking += remainder.thinking }
            if !remainder.answer.isEmpty { segment.answer += remainder.answer }
            segment.isThinkingActive = false
            segment.thinkingFinishedAt = segment.thinkingFinishedAt ?? Date()
            liveStreamSegments[msgID] = segment
        } else if var segment = liveStreamSegments[msgID] {
            segment.isThinkingActive = false
            segment.thinkingFinishedAt = segment.thinkingFinishedAt ?? Date()
            liveStreamSegments[msgID] = segment
        }

        var answer = (liveStreamSegments[msgID]?.answer ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let thinking = (liveStreamSegments[msgID]?.thinking ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Some Ollama reasoning models emit the entire reply on the thinking channel.
        // Promote a best-effort final reply so the bubble does not vanish.
        if answer.isEmpty, !thinking.isEmpty {
            answer = Self.extractLikelyFinalReply(from: thinking) ?? thinking
            if var segment = liveStreamSegments[msgID] {
                segment.answer = answer
                liveStreamSegments[msgID] = segment
            }
        }
        if !thinking.isEmpty {
            archiveThinkingIfNeeded(msgID: msgID)
        }

        if !answer.isEmpty {
            if let idx = messages.firstIndex(where: { $0.msgID == msgID }) {
                messages[idx] = CoworkMessage(
                    localID: msgID,
                    conversationID: conversationID,
                    position: "left",
                    text: answer
                )
            } else {
                messages.append(CoworkMessage(
                    localID: msgID,
                    conversationID: conversationID,
                    position: "left",
                    text: answer
                ))
            }
        }

        liveStreamSegments.removeValue(forKey: msgID)
        resetAnswerTypewriter(msgID: msgID)
        streamCoalescer.reset(msgID: msgID)
        persistDirectChatTranscript(conversationID: conversationID)
        publishStreamUI(urgent: true)
    }

    /// Pull the user-facing draft out of a verbose reasoning dump when Ollama left `content` empty.
    private static func extractLikelyFinalReply(from thinking: String) -> String? {
        let markers = [
            "Final Output Generation",
            "Draft Response",
            "I'll output this refined version",
            "Final plan:",
            "Final answer:",
        ]
        let lower = thinking.lowercased()
        var bestEnd: String.Index?
        for marker in markers {
            if let range = lower.range(of: marker.lowercased()) {
                if bestEnd == nil || range.upperBound > bestEnd! {
                    bestEnd = range.upperBound
                }
            }
        }
        guard let bestEnd else { return nil }
        if let blank = thinking.range(of: "\n\n", range: bestEnd..<thinking.endIndex) {
            let candidate = String(thinking[blank.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= 40 { return candidate }
        }
        let tail = String(thinking[bestEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.count >= 40 ? tail : nil
    }

    func chatOnlyCreateOverrides(model: String) -> CoworkConversationOverrides {
        let disabledSkills = availableSkills.map(\.name)
        return CoworkConversationOverrides(
            model: model,
            permission: agentPermissionMode,
            mcpIDs: [],
            skillIDs: [],
            disabledBuiltinSkillIDs: disabledSkills
        )
    }

    func chatOnlyCreateExtra(
        workspace: String?,
        customWorkspace: Bool,
        defaultFiles: [String]?
    ) -> CoworkConversationExtra {
        let disabledSkills = availableSkills.map(\.name)
        return CoworkConversationExtra(
            workspace: workspace,
            customWorkspace: customWorkspace,
            defaultFiles: defaultFiles,
            selectedMcpServerIDs: [],
            selectedSessionMcpServers: [],
            presetContext: L10n.chatOnlyPresetContext,
            enabledSkills: [],
            excludeBuiltinSkills: disabledSkills,
            excludeAutoInjectSkills: disabledSkills
        )
    }

    static func isStaleToolRejection(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("provider rejected")
            || lower.contains("rejected the request")
            || lower.contains("tool schema")
            || lower.contains("invalid tool")
            || lower.contains("model provider rejected")
    }

    var preferredLocalBackend: CoworkLocalLLMBackend {
        let raw = UserDefaults.standard.string(forKey: "cowork.localLLMBackend") ?? CoworkLocalLLMBackend.ollama.rawValue
        return CoworkLocalLLMBackend(rawValue: raw) ?? .ollama
    }

    var preferredMLXRepoID: String {
        let stored = UserDefaults.standard.string(forKey: "cowork.selectedMLXRepoID") ?? ""
        if !stored.isEmpty { return stored }
        return mlxInstalledModels.first?.id ?? CoworkMLXModelCatalog.defaultRepoID
    }

    func persistModelSelection() {
        if let providerID = selectedProviderID {
            UserDefaults.standard.set(providerID, forKey: Self.persistedProviderIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.persistedProviderIDKey)
        }
        if let modelID = selectedModelID {
            UserDefaults.standard.set(modelID, forKey: Self.persistedModelIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.persistedModelIDKey)
        }
    }

    /// Restores the last home-screen model choice saved before the previous app quit.
    private func restorePersistedModelSelection() {
        let storedModel = UserDefaults.standard.string(forKey: Self.persistedModelIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !storedModel.isEmpty else { return }

        let storedProvider = UserDefaults.standard.string(forKey: Self.persistedProviderIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !storedProvider.isEmpty,
           providers.contains(where: { $0.id == storedProvider }) {
            selectedProviderID = storedProvider
            // Always restore the model id — Ollama provider.models often lists only one tag,
            // so `contains` would wrongly drop qwen3.6:27b in favor of whatever was last registered.
            selectedModelID = storedModel
            return
        }

        if let provider = providers.first(where: { $0.models.contains(storedModel) }) {
            selectedProviderID = provider.id
            selectedModelID = storedModel
            return
        }

        // Provider list may lag behind Ollama tags — still restore the model id.
        selectedModelID = storedModel
    }

    var mlxRuntimeAvailable: Bool {
        CoworkMLXServerBridge.isMLXAvailable()
    }

    private var isLocalMLXModelSelection: Bool {
        if conversationUsesMLX(activeConversation) { return true }
        if let provider = selectedProvider, isLocalMLXProvider(provider) { return true }
        return false
    }

    func setThinkingCardExpanded(msgID: String, expanded: Bool) {
        if var segment = liveStreamSegments[msgID] {
            segment.thinkingCardExpanded = expanded
            liveStreamSegments[msgID] = segment
            return
        }
        guard var archived = archivedThinkingByMsgID[msgID] else { return }
        archived.cardExpanded = expanded
        archivedThinkingByMsgID[msgID] = archived
    }

    func closeConversation() {
        if !pendingConfirmations.isEmpty || activeConfirmation != nil {
            confirmationAnchorConversationID = activeConversationID
                ?? activeConfirmation?.conversationID
                ?? pendingConfirmations.first?.conversationID
                ?? confirmationAnchorConversationID
        }
        activeConversationID = nil
        activeConversation = nil
        messages = []
        clearLiveStreamSegments()
        archivedThinkingByMsgID = [:]
        liveToolCalls = [:]
        liveToolOrder = []
        thinkingParsers = [:]
        resetAnswerTypewriters()
        streamCoalescer.resetAll()
        workspaceEntries = []
        previewItems = []
        selectedPreviewID = nil
        // Keep pendingConfirmations / activeConfirmation — permission cards must survive tab switches.
        composerAttachments = []
        isStreaming = false
        // Keep activeTurnID so Stop can still cancel after reopen / from the global card.
        lastTokenUsage = nil
        conversationUsage = CoworkConversationUsageStats()
        restorePersistedModelSelection()
        if prefersCloudModelSelection {
            cancelInFlightMLXWarm()
        }
    }

    func loadConversationDetail(_ id: String) async {
        guard let client else { return }
        do {
            activeConversation = try await client.getConversation(id: id)
            if let ws = activeConversation?.workspacePath, !ws.isEmpty {
                workspacePath = ws
            }
            if let ref = activeConversation?.model {
                selectedProviderID = ref.providerID
                selectedModelID = ref.model
            }
            hydrateSessionConfig(from: activeConversation?.extra)
            await ensureConversationProvider()
            await applyToolCapabilityProfile()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    /// Restores per-session agent config (MCP, skills, permission) from the persisted conversation extra,
    /// so reopening a session shows the exact tool setup it was created with.
    private func hydrateSessionConfig(from extra: CoworkConversationExtra?) {
        guard let extra else { return }
        if let mcp = extra.selectedMcpServerIDs {
            selectedMcpIDs = Set(mcp)
            pruneMcpSelection()
        }
        if let skills = extra.skillIDs {
            selectedSkillIDs = Set(skills)
        }
        if let permission = extra.permission, !permission.isEmpty {
            agentPermissionMode = permission
        }
    }

    func loadMessages(for conversationID: String) async {
        guard let client else { return }
        do {
            let page = try await client.listMessages(conversationID: conversationID)
            let transcript = CoworkDirectChatStore.load(conversationID: conversationID)
            let local = CoworkDirectChatStore.coworkMessages(from: transcript)
            messages = CoworkDirectChatStore.merge(server: page.items, local: local)
            for (msgID, archived) in CoworkDirectChatStore.archivedThinking(from: transcript) {
                if archivedThinkingByMsgID[msgID] == nil {
                    archivedThinkingByMsgID[msgID] = archived
                }
            }
            hasMoreMessages = page.hasMore == true
            if !isStreaming {
                clearLiveStreamSegments()
                liveToolCalls = [:]
                liveToolOrder = []
                thinkingParsers = [:]
                resetAnswerTypewriters()
            }
            if let tip = page.items.last(where: { $0.isTips })?.errorMessage ?? page.items.last(where: { $0.isTips })?.textBody,
               !tip.isEmpty,
               !( !activeModelSupportsTools && Self.isStaleToolRejection(tip) ) {
                statusMessage = tip
            } else if !activeModelSupportsTools {
                statusMessage = nil
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Snapshot direct-chat turns so view reloads / turn-complete hooks cannot erase them.
    private func persistDirectChatTranscript(conversationID: String) {
        CoworkDirectChatStore.save(
            conversationID: conversationID,
            messages: messages.filter {
                ($0.conversationID == conversationID || $0.conversationID == nil)
                    && !$0.isTips
                    && !$0.isToolMessage
            },
            thinkingByMsgID: archivedThinkingByMsgID
        )
    }

    func loadOlderMessages() async {
        guard let client, let conversationID = activeConversationID,
              let beforeID = messages.first?.msgID ?? messages.first?.id else { return }
        do {
            let page = try await client.listMessages(conversationID: conversationID, limit: 50, before: beforeID)
            messages = page.items + messages
            hasMoreMessages = page.hasMore == true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func renameConversation(_ id: String, name: String) async {
        guard let client else { return }
        do {
            let updated = try await client.updateConversation(id: id, name: name)
            if activeConversationID == id { activeConversation = updated }
            await refreshConversations()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Switches the model used by the active conversation (Murmura-style mid-chat swap).
    func switchActiveConversationModel(providerID: String, model: String) async {
        guard let client, let conversationID = activeConversationID else { return }
        do {
            let updated = try await client.updateConversation(
                id: conversationID,
                CoworkUpdateConversationRequest(model: CoworkProviderModelRef(providerID: providerID, model: model))
            )
            activeConversation = updated
            selectedProviderID = providerID
            selectedModelID = model
            statusMessage = nil
            persistModelSelection()
            if cloudProviders.contains(where: { $0.id == providerID }) {
                cancelInFlightMLXWarm()
                UserDefaults.standard.set(CoworkModelPickerTab.cloud.rawValue, forKey: Self.modelPickerTabKey)
            } else if let provider = providers.first(where: { $0.id == providerID }) {
                if isLocalMLXProvider(provider) {
                    UserDefaults.standard.set(CoworkModelPickerTab.mlx.rawValue, forKey: Self.modelPickerTabKey)
                } else if Self.isOllamaEndpoint(provider.baseURL) {
                    UserDefaults.standard.set(CoworkModelPickerTab.ollama.rawValue, forKey: Self.modelPickerTabKey)
                }
            }
            await applyToolCapabilityProfile()
            await refreshConversations()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Switches the assistant mid-session: PATCHes the conversation profile and rebuilds the runtime.
    func switchActiveConversationAssistant(_ assistantID: String) async {
        selectedAssistantID = assistantID
        guard let client, let conversationID = activeConversationID else { return }
        await applyToolCapabilityProfile()
        try? await client.ensureRuntime(conversationID: conversationID)
        await refreshConversations()
    }

    /// Switch the active conversation to an MLX model: boot server, register provider, PATCH conversation.
    func switchActiveConversationToMLX(_ repoID: String) async {
        guard await selectMLXModel(repoID) else { return }
        if let providerID = selectedProviderID {
            await switchActiveConversationModel(providerID: providerID, model: repoID)
        }
    }

    /// Persists MCP tool selection for the active conversation (merged into extra).
    func applyMcpSelectionToActiveConversation() async {
        guard let client, let conversationID = activeConversationID else { return }
        guard activeModelSupportsTools else { return }
        do {
            let updated = try await client.updateConversation(
                id: conversationID,
                CoworkUpdateConversationRequest(
                    extra: CoworkConversationExtra(selectedMcpServerIDs: effectiveMcpIDs),
                    mergeExtra: true
                )
            )
            activeConversation = updated
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    func refreshSkills() async {
        guard let client else { return }
        do {
            let raw = try await client.listSkills()
            var seen = Set<String>()
            availableSkills = raw.filter { skill in
                let key = skill.name.lowercased()
                return seen.insert(key).inserted
            }
        } catch {
            availableSkills = []
        }
    }

    func refreshSlashCommands() async {
        guard let client, let conversationID = activeConversationID else { return }
        do {
            slashCommands = try await client.listSlashCommands(conversationID: conversationID)
        } catch {
            slashCommands = []
        }
    }

    func refreshMLXModels() {
        mlxInstalledModels = CoworkMLXInstalledScanner.installedModels(
            from: CoworkMLXModelLibrary.shared.installedByteSizes
        )
    }

    func refreshMLXModelsAsync() async {
        await CoworkMLXModelLibrary.shared.refreshInstalledByteSizesAsync()
        refreshMLXModels()
    }

    func refreshFileChanges() async {
        guard let client, let workspace = activeConversation?.workspacePath ?? Optional(workspacePath).flatMap({ $0.isEmpty ? nil : $0 }) else {
            fileChanges = []
            return
        }
        do {
            try? await client.initFileSnapshot(workspace: workspace)
            let result = try await client.compareFileSnapshot(workspace: workspace)
            fileChanges = result.allChanges
        } catch {
            fileChanges = []
        }
    }

    /// Re-bind conversation model to a live provider (repairProviders can orphan provider ids).
    func ensureConversationProvider() async {
        guard let ref = activeConversation?.model else { return }
        let model = ref.model
        let providerID = ref.providerID

        if providers.contains(where: { $0.id == providerID && ($0.models.contains(model) || $0.enabled != false) }) {
            selectedProviderID = providerID
            selectedModelID = model
            return
        }

        if let match = providers.first(where: { $0.models.contains(model) && $0.enabled != false }) {
            await switchActiveConversationModel(providerID: match.id, model: model)
            return
        }

        if ollamaChatModels.contains(where: { $0.name == model }) {
            await selectOllamaModel(model)
            if let pid = selectedProviderID {
                await switchActiveConversationModel(providerID: pid, model: model)
            }
        }
    }

    /// Infer provider platform for error localization (OpenAI cloud even when provider id is stale).
    func resolvedProviderPlatform() -> String? {
        if let platform = selectedProvider?.platform, !platform.isEmpty {
            return platform
        }
        if let providerID = activeConversation?.model?.providerID ?? selectedProviderID,
           let provider = providers.first(where: { $0.id == providerID }) {
            return provider.platform
        }
        let model = (resolvedModelID ?? selectedModelID ?? "").lowercased()
        if model.contains("gpt") { return "openai" }
        if model.contains("claude") { return "anthropic" }
        if model.contains("gemini") { return "gemini" }
        if model.contains("grok") || model.contains("xai") { return "xai" }
        return nil
    }

    func localizedStatus(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if !activeModelSupportsTools && Self.isStaleToolRejection(raw) { return nil }
        let platform = resolvedProviderPlatform()
        let normalized = Self.normalizeStaleRejectionMessage(raw, platform: platform)
        return L10n.statusLine(
            normalized,
            chatOnly: !activeModelSupportsTools,
            providerPlatform: platform,
            mcpCount: selectedEnabledMcpCount
        )
    }

    /// Maps cached Ollama-flavoured rejections back to raw tokens for re-localization with cloud platform.
    static func normalizeStaleRejectionMessage(_ raw: String, platform: String?) -> String {
        let lower = raw.lowercased()
        if lower.contains("qwen3.6") || lower.contains("avec ollama") || lower.contains("with ollama") {
            if platform?.lowercased() != "ollama" {
                return "model provider rejected the request"
            }
        }
        return raw
    }

    /// MCP defaults: curated safe subset for cloud BYOK on first use only; never override an explicit user choice.
    func applyMcpDefaultsForSelectedProvider() {
        guard !UserDefaults.standard.bool(forKey: Self.mcpUserConfiguredKey) else { return }
        guard let provider = selectedProvider else { return }
        let profile = CoworkModelToolSupport.mcpToolProfile(platform: provider.platform)
        if CoworkModelToolSupport.prefersCuratedMcp(platform: provider.platform) {
            if selectedMcpIDs.isEmpty {
                selectedMcpIDs = CoworkMcpCurator.defaultSelectedIDs(servers: mcpServers, profile: profile)
            } else {
                selectedMcpIDs = curatedMcpSelection()
            }
        } else if selectedMcpIDs.isEmpty {
            selectedMcpIDs = Set(mcpServers.filter(\.enabled).map(\.id))
        }
    }

    func sendFromHome(retryWithoutMcp: Bool = false) async {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = L10n.emptyMessage
            return
        }
        guard hasResolvableModelSelection else {
            statusMessage = L10n.selectModelFirst
            return
        }

        isSending = true

        do {
            try await ensureCoreReady()
        } catch {
            statusMessage = L10n.coreNotReady
            isSending = false
            return
        }

        guard let client else {
            statusMessage = L10n.coreNotReady
            isSending = false
            return
        }

        await syncLocalBackendSelection()

        if preferredLocalBackend == .mlx, !shouldDeferLocalMLXActivation() {
            let target = resolvedHomeModelID ?? ""
            do {
                try await ensureMLXReadyForSend(repoID: target)
            } catch CoworkMLXBridgeError.modelNotInstalled {
                statusMessage = L10n.mlxModelNotInstalled
                isSending = false
                return
            } catch {
                statusMessage = L10n.localizeError(
                    CoworkMLXModelLibrary.enrichedLoadErrorMessage(error.localizedDescription)
                )
                isSending = false
                return
            }
        }

        guard let provider = selectedProvider, let model = resolvedHomeModelID else {
            statusMessage = L10n.selectModelFirst
            isSending = false
            return
        }
        guard let assistant = selectedAssistant else {
            statusMessage = L10n.noAssistant
            isSending = false
            return
        }

        statusMessage = nil

        do {
            if availableSkills.isEmpty { await refreshSkills() }
            if !retryWithoutMcp, shouldUseAgentToolPipeline() {
                await prepareMcpSelectionForSend()
            }
            let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let mcpIDs = retryWithoutMcp ? [] : effectiveMcpIDs
            let skillIDs = effectiveSkillIDs
            let useTools = !retryWithoutMcp && shouldUseAgentToolPipeline(mcpIDs: mcpIDs, skillIDs: skillIDs)
            let attachmentPathsToSend = attachmentPaths
            let fileRefs = useTools ? CoworkChatFileRef.localRefs(from: attachmentPathsToSend) : []
            let request = CoworkCreateConversationRequest(
                name: String(text.prefix(80)),
                model: CoworkProviderModelRef(providerID: provider.id, model: model),
                assistant: CoworkAssistantRef(
                    id: assistant.id,
                    locale: CitadelLocale.current.rawValue,
                    conversationOverrides: useTools
                        ? CoworkConversationOverrides(
                            model: model,
                            permission: agentPermissionMode,
                            mcpIDs: mcpIDs,
                            skillIDs: skillIDs
                        )
                        : chatOnlyCreateOverrides(model: model)
                ),
                extra: useTools
                    ? CoworkConversationExtra(
                        workspace: workspace.isEmpty ? nil : workspace,
                        customWorkspace: !workspace.isEmpty,
                        defaultFiles: attachmentPaths.isEmpty ? nil : attachmentPaths,
                        selectedMcpServerIDs: mcpIDs,
                        skillIDs: skillIDs
                    )
                    : chatOnlyCreateExtra(
                        workspace: workspace.isEmpty ? nil : workspace,
                        customWorkspace: !workspace.isEmpty,
                        defaultFiles: attachmentPaths.isEmpty ? nil : attachmentPaths
                    )
            )
            let conversation = try await client.createConversation(request)
            // Open the session + stamp the user bubble before enrichment/stream.
            promptText = ""
            attachmentPaths = []
            indexedAttachmentPaths = []
            messages = [
                CoworkMessage(
                    localID: UUID().uuidString,
                    conversationID: conversation.id,
                    position: "right",
                    text: text
                )
            ]
            activeConversationID = conversation.id
            activeConversation = conversation
            persistDirectChatTranscript(conversationID: conversation.id)
            persistModelSelection()
            await refreshConversations()
            await loadConversationDetail(conversation.id)
            isSending = false

            let enriched = await enrichMessageWithDocuments(text, attachmentPaths: attachmentPathsToSend)
            if !attachmentPathsToSend.isEmpty {
                await ingestAttachments(attachmentPathsToSend)
            }

            if usesDirectCloudChat {
                await prepareConversationRuntimeBeforeSend(conversationID: conversation.id)
                try await sendViaDirectCloudChat(
                    conversationID: conversation.id,
                    text: enriched,
                    provider: provider,
                    model: model,
                    preStampedUserID: messages.first(where: \.isUser)?.msgID
                )
                await refreshConversations()
                return
            }

            if usesDirectOllamaChat {
                try await sendViaDirectOllamaChat(
                    conversationID: conversation.id,
                    text: enriched,
                    provider: provider,
                    model: model,
                    preStampedUserID: messages.first(where: \.isUser)?.msgID,
                    preStampedUserText: text
                )
                await refreshConversations()
                return
            }

            isSending = true
            await prepareConversationRuntimeBeforeSend(conversationID: conversation.id)
            let result = try await client.sendMessage(conversationID: conversation.id, input: enriched, files: fileRefs)
            activeTurnID = result.turnID
            statusMessage = nil
            isSending = false
            isStreaming = true
            await loadMessages(for: conversation.id)
            await refreshWorkspace()
        } catch {
            isSending = false
            let raw = error.localizedDescription
            if !retryWithoutMcp,
               isCloudModelSelection,
               let provider = selectedProvider,
               let model = resolvedHomeModelID,
               let conversationID = activeConversationID {
                do {
                    try await sendViaDirectCloudChat(
                        conversationID: conversationID,
                        text: text,
                        provider: provider,
                        model: model,
                        preStampedUserID: messages.first(where: \.isUser)?.msgID
                    )
                    return
                } catch {
                    statusMessage = L10n.localizeError(error.localizedDescription, providerPlatform: provider.platform)
                    return
                }
            }
            if !retryWithoutMcp, Self.isStaleToolRejection(raw), shouldUseAgentToolPipeline() {
                selectedMcpIDs = []
                selectedSkillIDs = []
                await applyToolCapabilityProfile()
                if activeConversationID != nil {
                    await sendInConversation(text, retryWithoutMcp: true)
                } else {
                    await sendFromHome(retryWithoutMcp: true)
                }
                return
            }
            statusMessage = raw
        }
    }

    func sendInConversation(_ text: String, retryWithoutMcp: Bool = false) async {
        guard let client, let conversationID = activeConversationID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isSending || isStreaming {
            pendingCommands.append(trimmed)
            return
        }

        let useDirectOllama = usesDirectOllamaChat
        let useDirectCloud = usesDirectCloudChat

        // Stamp the user bubble immediately — don't wait on runtime/MCP/enrichment.
        let stampedUserID: String? = (useDirectOllama || useDirectCloud) ? UUID().uuidString : nil
        if let stampedUserID {
            messages.append(CoworkMessage(
                localID: stampedUserID,
                conversationID: conversationID,
                position: "right",
                text: trimmed
            ))
            persistDirectChatTranscript(conversationID: conversationID)
        }

        isSending = true
        do {
            await ensureConversationProvider()
            if conversationUsesMLX(activeConversation),
               let mlxModel = activeConversation?.model?.model {
                try await ensureMLXReadyForSend(repoID: mlxModel)
            }
            if !retryWithoutMcp, shouldUseAgentToolPipeline() {
                await prepareMcpSelectionForSend()
            }
            if !useDirectOllama && !useDirectCloud {
                await prepareConversationRuntimeBeforeSend(conversationID: conversationID)
            }

            if useDirectCloud {
                let ref = activeConversation?.model
                let provider = ref.flatMap { r in providers.first { $0.id == r.providerID } } ?? selectedProvider
                let model = ref?.model ?? selectedModelID
                guard let provider, let model else {
                    statusMessage = L10n.selectModelFirst
                    isSending = false
                    return
                }
                isSending = false
                try await sendViaDirectCloudChat(
                    conversationID: conversationID,
                    text: trimmed,
                    provider: provider,
                    model: model,
                    preStampedUserID: stampedUserID
                )
                return
            }

            if useDirectOllama {
                let ref = activeConversation?.model
                let provider = ref.flatMap { r in providers.first { $0.id == r.providerID } } ?? selectedProvider
                let model = ref?.model ?? selectedModelID
                guard let provider, let model else {
                    statusMessage = L10n.selectModelFirst
                    isSending = false
                    return
                }
                let attachmentPathsToSend = composerAttachments
                // Clear sending before enrichment/stream so the banner doesn't stick on "Sending…".
                isSending = false
                let enriched = await enrichMessageWithDocuments(trimmed, attachmentPaths: attachmentPathsToSend)
                composerAttachments = []
                indexedAttachmentPaths = []
                if !attachmentPathsToSend.isEmpty {
                    await ingestAttachments(attachmentPathsToSend)
                }
                try await sendViaDirectOllamaChat(
                    conversationID: conversationID,
                    text: enriched,
                    provider: provider,
                    model: model,
                    preStampedUserID: stampedUserID,
                    preStampedUserText: trimmed
                )
                return
            }

            let attachmentPathsToSend = composerAttachments
            let enriched = await enrichMessageWithDocuments(trimmed, attachmentPaths: attachmentPathsToSend)
            let fileRefs = shouldUseAgentToolPipeline() ? CoworkChatFileRef.localRefs(from: attachmentPathsToSend) : []
            composerAttachments = []
            indexedAttachmentPaths = []
            if !attachmentPathsToSend.isEmpty {
                await ingestAttachments(attachmentPathsToSend)
            }
            let result = try await client.sendMessage(conversationID: conversationID, input: enriched, files: fileRefs)
            activeTurnID = result.turnID
            statusMessage = nil
            isSending = false
            isStreaming = true
            await loadMessages(for: conversationID)
            await refreshWorkspace()
        } catch {
            isSending = false
            let raw = error.localizedDescription
            if !retryWithoutMcp,
               let provider = selectedProvider,
               let model = activeConversation?.model?.model ?? selectedModelID,
               isCloudConversation(activeConversation) {
                do {
                    try await sendViaDirectCloudChat(
                        conversationID: conversationID,
                        text: trimmed,
                        provider: provider,
                        model: model
                    )
                    return
                } catch {
                    statusMessage = L10n.localizeError(error.localizedDescription, providerPlatform: provider.platform)
                    return
                }
            }
            if !retryWithoutMcp, Self.isStaleToolRejection(raw), shouldUseAgentToolPipeline() {
                selectedMcpIDs = []
                selectedSkillIDs = []
                await applyToolCapabilityProfile()
                await sendInConversation(trimmed, retryWithoutMcp: true)
                return
            }
            statusMessage = raw
        }
    }

    func stopGeneration() async {
        let conversationID = activeConversationID
            ?? activeConfirmation?.conversationID
            ?? pendingConfirmations.first?.conversationID
            ?? confirmationAnchorConversationID
        guard let client, let conversationID, let turnID = activeTurnID else { return }
        do {
            try await client.cancelTurn(conversationID: conversationID, turnID: turnID)
            isStreaming = false
            activeTurnID = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteConversation(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteConversation(id: id)
            if activeConversationID == id { closeConversation() }
            if confirmationAnchorConversationID == id
                || activeConfirmation?.conversationID == id
                || pendingConfirmations.contains(where: { $0.conversationID == id }) {
                pendingConfirmations.removeAll { $0.conversationID == id || $0.conversationID == nil }
                if activeConfirmation?.conversationID == id {
                    activeConfirmation = pendingConfirmations.first
                }
                if confirmationAnchorConversationID == id {
                    confirmationAnchorConversationID = activeConfirmation?.conversationID
                }
            }
            await refreshConversations()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addProvider(
        preset: CoworkProviderPreset,
        name: String,
        baseURL: String,
        apiKey: String,
        modelID: String
    ) async throws {
        try await addProvider(
            preset: preset,
            name: name,
            baseURL: baseURL,
            apiKey: apiKey,
            modelID: modelID,
            resolvedBaseURL: nil
        )
    }

    func addProvider(
        preset: CoworkProviderPreset,
        name: String,
        baseURL: String,
        apiKey: String,
        modelID: String,
        resolvedBaseURL: String?
    ) async throws {
        guard let client else { throw CoworkCoreError.notConnected }
        let normalized = CoworkOllamaModelsAPI.normalizedChatBaseURL(resolvedBaseURL ?? baseURL)
        let provider = try await client.createProvider(
            CoworkCreateProviderRequest(
                platform: preset.platform,
                name: name,
                baseURL: normalized,
                apiKey: apiKey,
                models: [modelID],
                enabled: true
            )
        )
        providers = try await client.listProviders()
        selectedProviderID = provider.id
        selectedModelID = modelID
        persistModelSelection()
    }

    func discoverModels(preset: CoworkProviderPreset, baseURL: String, apiKey: String) async throws -> (models: [CoworkModelOption], fixedBaseURL: String?) {
        guard let client else { throw CoworkCoreError.notConnected }
        let response = try await client.fetchModels(
            CoworkFetchModelsRequest(platform: preset.platform, baseURL: baseURL, apiKey: apiKey, tryFix: true)
        )
        return (response.models, response.fixedBaseURL)
    }

    func refreshOllamaModels() async {
        isLoadingOllamaModels = true
        defer { isLoadingOllamaModels = false }
        mlxInstalledModels = CoworkMLXInstalledScanner.installedModels()
        do {
            let models = try await CoworkOllamaModelsAPI.fetchInstalledModels(baseURL: "http://127.0.0.1:11434")
            ollamaChatModels = models.filter { !$0.isEmbedding }
            ollamaReachable = true

            let persisted = UserDefaults.standard.string(forKey: Self.persistedModelIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pickerTab = UserDefaults.standard.string(forKey: Self.modelPickerTabKey)

            // Re-assert persisted Ollama selection after tags load (do not fall back to first model).
            if pickerTab != CoworkModelPickerTab.cloud.rawValue,
               pickerTab != CoworkModelPickerTab.mlx.rawValue,
               !persisted.isEmpty,
               ollamaChatModels.contains(where: { $0.name == persisted }) {
                if activeConversationID == nil {
                    await selectOllamaModel(persisted)
                } else if selectedModelID != persisted, isCloudModelSelection {
                    // Conversation owns the model; keep picker tab local without forcing a swap.
                    selectedModelID = activeConversation?.model?.model ?? selectedModelID
                }
            } else if selectedModelID == nil, activeConversationID == nil, !isCloudModelSelection,
                      let first = ollamaChatModels.first {
                await selectOllamaModel(first.name)
            }
        } catch {
            ollamaReachable = false
            ollamaChatModels = []
        }
    }

    func selectOllamaModel(_ name: String) async {
        UserDefaults.standard.set(CoworkLocalLLMBackend.ollama.rawValue, forKey: "cowork.localLLMBackend")
        UserDefaults.standard.set(CoworkModelPickerTab.ollama.rawValue, forKey: "cowork.modelPickerTab")
        selectedModelID = name
        // Persist immediately so a later refresh/repair cannot fall back to models.first.
        persistModelSelection()
        guard let client else { return }

        if let existing = providers.first(where: { Self.isOllamaEndpoint($0.baseURL) }) {
            selectedProviderID = existing.id
            var models = existing.models
            if let idx = models.firstIndex(of: name) {
                models.remove(at: idx)
            }
            models.insert(name, at: 0)
            if models != existing.models {
                do {
                    _ = try await client.updateProvider(
                        id: existing.id,
                        CoworkUpdateProviderRequest(models: models)
                    )
                    providers = try await client.listProviders()
                } catch {
                    statusMessage = L10n.localizeError(error.localizedDescription)
                }
            }
        } else {
            do {
                try await addProvider(
                    preset: .ollama,
                    name: "Ollama",
                    baseURL: "http://127.0.0.1:11434",
                    apiKey: "ollama",
                    modelID: name,
                    resolvedBaseURL: "http://127.0.0.1:11434/v1"
                )
            } catch {
                statusMessage = L10n.localizeError(error.localizedDescription)
                return
            }
        }
        if activeConversationID != nil, let providerID = selectedProviderID {
            await switchActiveConversationModel(providerID: providerID, model: name)
        }
        persistModelSelection()
    }

    private static func isOllamaEndpoint(_ baseURL: String) -> Bool {
        let base = baseURL.lowercased()
        return base.contains("11434") || base.contains("/ollama")
    }

    func selectCloudModel(providerID: String, model: String) async {
        cancelInFlightMLXWarm()
        UserDefaults.standard.set(CoworkModelPickerTab.cloud.rawValue, forKey: Self.modelPickerTabKey)
        selectedProviderID = providerID
        selectedModelID = model
        statusMessage = nil
        if activeConversationID != nil {
            await switchActiveConversationModel(providerID: providerID, model: model)
        }
        persistModelSelection()
    }

    /// Infers which picker tab matches the current provider/model selection.
    var inferredModelPickerTab: CoworkModelPickerTab {
        if let providerID = selectedProviderID,
           cloudProviders.contains(where: { $0.id == providerID }) {
            return .cloud
        }
        if let model = selectedModelID,
           mlxInstalledModels.contains(where: { $0.id == model }) {
            return .mlx
        }
        return .ollama
    }

    func selectMLXModel(_ repoID: String) async -> Bool {
        do {
            try await ensureCoreReady()
            try await activateMLXModel(repoID)
            UserDefaults.standard.set(CoworkLocalLLMBackend.mlx.rawValue, forKey: "cowork.localLLMBackend")
            UserDefaults.standard.set(CoworkModelPickerTab.mlx.rawValue, forKey: "cowork.modelPickerTab")
            UserDefaults.standard.set(repoID, forKey: "cowork.selectedMLXRepoID")
            return true
        } catch {
            statusMessage = L10n.localizeError(
                CoworkMLXModelLibrary.enrichedLoadErrorMessage(error.localizedDescription)
            )
            return false
        }
    }

    /// Starts the MLX server for `repoID` and points selection at a provider that lists it.
    /// Throws instead of silently leaving a stale (e.g. Ollama) selection in place.
    func activateMLXModel(_ repoID: String, updateSelection: Bool = true) async throws {
        guard let client else { throw CoworkCoreError.notConnected }
        try await CoworkMLXServerBridge.startIfNeeded(repoID: repoID) { message in
            guard updateSelection, !self.shouldDeferLocalMLXActivation() else { return }
            self.mlxRuntimeInstallMessage = message
        }
        let normalized = CoworkOllamaModelsAPI.normalizedChatBaseURL(CoworkMLXServerBridge.chatBaseURL())
        if let existing = providers.first(where: {
            CoworkOllamaModelsAPI.normalizedChatBaseURL($0.baseURL) == normalized
        }) {
            if !existing.models.contains(repoID) {
                var updated = existing
                updated.models.append(repoID)
                _ = try await client.updateProvider(
                    id: existing.id,
                    CoworkUpdateProviderRequest(models: updated.models)
                )
                providers = try await client.listProviders()
            }
            guard updateSelection else {
                mlxRuntimeInstallMessage = nil
                return
            }
            guard !shouldDeferLocalMLXActivation() else {
                mlxRuntimeInstallMessage = nil
                return
            }
            selectedProviderID = existing.id
            selectedModelID = repoID
            statusMessage = nil
            mlxRuntimeInstallMessage = nil
            persistModelSelection()
            return
        }
        if updateSelection, shouldDeferLocalMLXActivation() {
            mlxRuntimeInstallMessage = nil
            return
        }
        let previousProviderID = selectedProviderID
        let previousModelID = selectedModelID
        try await addProvider(
            preset: .custom,
            name: "Native MLX",
            baseURL: normalized,
            apiKey: "mlx",
            modelID: repoID,
            resolvedBaseURL: normalized
        )
        if updateSelection, shouldDeferLocalMLXActivation() {
            selectedProviderID = previousProviderID
            selectedModelID = previousModelID
        }
        statusMessage = nil
        mlxRuntimeInstallMessage = nil
        if updateSelection, !shouldDeferLocalMLXActivation() {
            persistModelSelection()
        }
    }

    func repairProviders() async {
        guard let client else { return }
        var seenKeys = Set<String>()
        var canonicalByKey: [String: String] = [:]
        var idRemap: [String: String] = [:]
        var deleteIDs: [String] = []
        for provider in providers {
            let normalized = CoworkOllamaModelsAPI.normalizedChatBaseURL(provider.baseURL)
            let key = "\(provider.platform)|\(normalized)"
            if seenKeys.contains(key) {
                deleteIDs.append(provider.id)
                if let kept = canonicalByKey[key] {
                    idRemap[provider.id] = kept
                }
                continue
            }
            seenKeys.insert(key)
            canonicalByKey[key] = provider.id
            if normalized != provider.baseURL {
                _ = try? await client.updateProvider(
                    id: provider.id,
                    CoworkUpdateProviderRequest(baseURL: normalized)
                )
            }
            if !provider.models.isEmpty,
               selectedProviderID == nil,
               !persistedPrefersCloudModel() {
                selectedProviderID = provider.id
                if selectedModelID == nil || selectedModelID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    selectedModelID = provider.models.first
                }
            }
        }
        for id in deleteIDs {
            try? await client.deleteProvider(id: id)
        }
        do {
            providers = try await client.listProviders()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
        if let ref = activeConversation?.model, let newID = idRemap[ref.providerID] {
            await switchActiveConversationModel(providerID: newID, model: ref.model)
        }
    }

    func pickWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.useFolder
        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
        }
    }

    func pickAttachments(target: AttachmentTarget = .home) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.attachFiles
        if panel.runModal() == .OK {
            let paths = panel.urls.map(\.path)
            switch target {
            case .home:
                attachmentPaths.append(contentsOf: paths)
            case .composer:
                composerAttachments.append(contentsOf: paths)
            }
            if let last = paths.last {
                previewLocalAttachment(last)
            }
            indexAttachmentPaths(paths)
        }
    }

    private func indexAttachmentPaths(_ paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if CoworkDocumentTextExtractor.extractText(from: url) != nil {
                indexedAttachmentPaths.insert(path)
            }
        }
    }

    enum AttachmentTarget { case home, composer }

    func removeAttachment(_ path: String, target: AttachmentTarget = .home) {
        switch target {
        case .home:
            attachmentPaths.removeAll { $0 == path }
            indexedAttachmentPaths.remove(path)
        case .composer:
            composerAttachments.removeAll { $0 == path }
            indexedAttachmentPaths.remove(path)
        }
    }

    /// Prepends extracted document text so chat-only models can answer (Murmura-style indexing).
    func enrichMessageWithDocuments(_ text: String, attachmentPaths: [String]) async -> String {
        var paths = attachmentPaths
        let workspace = activeConversation?.workspacePath ?? (workspacePath.isEmpty ? nil : workspacePath)
        if let workspace, !workspace.isEmpty {
            let workspaceMatches = await CoworkWorkspaceDocumentMatcher.matchingPaths(workspace: workspace, query: text)
            paths.append(contentsOf: workspaceMatches)
        }
        paths = Array(Set(paths))

        guard !paths.isEmpty else { return text }

        var blocks: [String] = []
        var indexed = Set<String>()
        var totalChars = 0
        let maxTotal = CoworkDocumentTextExtractor.maxCharacters

        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let content = CoworkDocumentTextExtractor.extractText(from: url)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else { continue }

            let name = (path as NSString).lastPathComponent
            let remaining = maxTotal - totalChars
            guard remaining > 400 else { break }
            let clipped = content.count > remaining
                ? String(content.prefix(remaining)) + "\n… [truncated]"
                : content
            blocks.append("--- \(name) ---\n\(clipped)")
            totalChars += clipped.count
            indexed.insert(path)
        }

        indexedAttachmentPaths.formUnion(indexed)
        guard !blocks.isEmpty else { return text }

        return CoworkDocumentContextParser.wrapDocumentBlocks(blocks, userText: text)
    }

    /// Workspace documents to inline: filename, Spotlight content, local text, then open questions.
    func workspaceDocumentPaths(matching query: String) async -> [String] {
        let workspace = activeConversation?.workspacePath ?? (workspacePath.isEmpty ? nil : workspacePath)
        guard let workspace, !workspace.isEmpty else { return [] }
        return await CoworkWorkspaceDocumentMatcher.matchingPaths(workspace: workspace, query: query)
    }

    /// Copies picker attachments into the conversation workspace and refreshes the file list.
    func ingestAttachments(_ paths: [String]) async {
        guard let client, !paths.isEmpty else { return }
        let workspace = activeConversation?.workspacePath ?? (workspacePath.isEmpty ? nil : workspacePath)
        guard let workspace, !workspace.isEmpty else { return }
        do {
            let result = try await client.copyFilesToWorkspace(filePaths: paths, workspace: workspace)
            if let failed = result.failedFiles, !failed.isEmpty {
                let names = failed.map { "\(($0.path as NSString).lastPathComponent): \($0.message)" }.joined(separator: "; ")
                statusMessage = L10n.attachmentsCopyPartial(names)
            }
            await refreshWorkspace()
            if let first = result.copiedFiles?.first ?? paths.first {
                let title = (first as NSString).lastPathComponent
                await openPreview(path: (first as NSString).lastPathComponent, workspace: workspace, title: title)
            }
        } catch {
            CitadelLog.debug(CitadelLog.app, "Attachment ingest failed: \(error.localizedDescription)")
        }
    }

    /// Preview a file from the macOS picker before it is copied into the workspace.
    func previewLocalAttachment(_ path: String) {
        let title = (path as NSString).lastPathComponent
        let ext = (path as NSString).pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "svg"]
        let textExtensions = ["md", "markdown", "txt", "json", "swift", "py", "js", "ts", "html", "css", "sh", "yml", "yaml", "xml", "csv"]

        if imageExtensions.contains(ext), let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            upsertPreview(CoworkPreviewItem(
                id: path,
                title: title,
                path: path,
                content: "",
                contentType: .image,
                imageBase64: data.base64EncodedString()
            ))
            return
        }
        if ext == "pdf", let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            upsertPreview(CoworkPreviewItem(
                id: path,
                title: title,
                path: path,
                content: data.base64EncodedString(),
                contentType: .pdf,
                imageBase64: nil
            ))
            return
        }
        if textExtensions.contains(ext), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let type: CoworkPreviewContentType
            if ext == "html" || ext == "htm" { type = .html }
            else if ext == "md" || ext == "markdown" { type = .markdown }
            else { type = .code }
            upsertPreview(CoworkPreviewItem(id: path, title: title, path: path, content: text, contentType: type, imageBase64: nil))
            return
        }
        CoworkQuickLookController.shared.present(paths: [path])
    }

    func refreshMcpServers() async {
        guard let client else { return }
        do {
            mcpServers = try await client.listMcpServers()
            applyMcpDefaultsForSelectedProvider()
            if !selectedMcpIDs.isEmpty {
                pruneMcpSelection()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Drops disabled or removed MCP servers from the active session selection.
    func pruneMcpSelection() {
        let enabledIDs = Set(mcpServers.filter(\.enabled).map(\.id))
        selectedMcpIDs = selectedMcpIDs.intersection(enabledIDs)
    }

    var enabledMcpServers: [CoworkMcpServer] {
        mcpServers.filter(\.enabled)
    }

    var selectedEnabledMcpCount: Int {
        selectedMcpIDs.intersection(Set(enabledMcpServers.map(\.id))).count
    }

    func refreshMcpAgentConfigs() async {
        guard let client else { return }
        do {
            mcpAgentConfigs = try await client.listMcpAgentConfigs()
        } catch {
            // Optional catalog — don't block the rest of Cowork on this.
        }
    }

    func bootstrapDefaultMcpIfNeeded() async {
        guard let client else { return }
        let existingNames = Set(mcpServers.map(\.name))
        let imports = CoworkMcpBootstrap.serversToImport(providers: providers)
            .filter { !existingNames.contains($0.name) }
        guard !imports.isEmpty else { return }
        do {
            _ = try await client.importMcpServers(CoworkMcpImportRequest(servers: imports))
            await refreshMcpServers()
        } catch {
            // Individual servers may fail if node/npx unavailable.
        }
    }

    func importDetectedMcpServer(_ server: CoworkMcpDetectedServer) async {
        guard let client, let transport = server.transport else { return }
        var config: [String: Any] = [:]
        if transport.type == "stdio", let command = transport.command {
            config["command"] = command
            if let args = transport.args { config["args"] = args }
        } else if let url = transport.url {
            config["type"] = transport.type
            config["url"] = url
        }
        if let description = server.description { config["description"] = description }
        let originalJSON = (try? JSONSerialization.data(withJSONObject: ["mcpServers": [server.name: config]]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let importServer = CoworkMcpImportServer(
            name: server.name,
            description: server.description,
            transport: CoworkMcpTransport(type: transport.type, command: transport.command, args: transport.args, url: transport.url),
            originalJSON: originalJSON,
            builtin: server.builtin
        )
        do {
            _ = try await client.importMcpServers(CoworkMcpImportRequest(servers: [importServer]))
            await refreshMcpServers()
            await refreshMcpAgentConfigs()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setMcpServerEnabled(_ id: String, enabled: Bool) async {
        guard let current = mcpServers.first(where: { $0.id == id }) else { return }
        guard current.enabled != enabled else { return }
        await toggleMcpServer(id)
    }

    func toggleMcpServer(_ id: String) async {
        guard let client else { return }
        do {
            _ = try await client.toggleMcpServer(id: id)
            await refreshMcpServers()
            if let server = mcpServers.first(where: { $0.id == id }) {
                if server.enabled { selectedMcpIDs.insert(id) } else { selectedMcpIDs.remove(id) }
            }
            pruneMcpSelection()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteMcpServer(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteMcpServer(id: id)
            selectedMcpIDs.remove(id)
            await refreshMcpServers()
            pruneMcpSelection()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importMcpFromJSON(_ json: String) async throws {
        guard let client else { throw CoworkCoreError.notConnected }
        guard let data = json.data(using: .utf8) else {
            throw CoworkCoreError.backendError(code: 0, message: "Invalid JSON")
        }
        let raw = try JSONSerialization.jsonObject(with: data)

        let servers: [[String: Any]]
        if let dict = raw as? [String: Any], let mcpServers = dict["mcpServers"] as? [String: Any] {
            servers = mcpServers.map { key, value in
                var entry = (value as? [String: Any]) ?? [:]
                if entry["name"] == nil { entry["name"] = key }
                return entry
            }
        } else if let array = raw as? [[String: Any]] {
            servers = array
        } else {
            throw CoworkCoreError.backendError(code: 0, message: "Expected mcpServers object or array")
        }

        let imports: [CoworkMcpImportServer] = servers.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let jsonData = (try? JSONSerialization.data(withJSONObject: entry)) ?? Data()
            let original = String(data: jsonData, encoding: .utf8) ?? "{}"
            let transport: CoworkMcpTransport
            if let cmd = entry["command"] as? String {
                transport = CoworkMcpTransport(type: "stdio", command: cmd, args: entry["args"] as? [String], url: nil)
            } else if let url = entry["url"] as? String {
                transport = CoworkMcpTransport(type: "http", command: nil, args: nil, url: url)
            } else {
                transport = CoworkMcpTransport(type: "stdio", command: "npx", args: ["-y"], url: nil)
            }
            return CoworkMcpImportServer(
                name: name,
                description: entry["description"] as? String,
                transport: transport,
                originalJSON: original,
                builtin: nil
            )
        }

        _ = try await client.importMcpServers(CoworkMcpImportRequest(servers: imports))
        await refreshMcpServers()
    }

    func refreshWorkspace() async {
        guard let client, let conversationID = activeConversationID else { return }
        do {
            let raw = try await client.listWorkspace(
                conversationID: conversationID,
                path: workspaceRelativePath,
                search: workspaceSearchQuery.isEmpty ? nil : workspaceSearchQuery
            )
            workspaceEntries = raw.filter { !Self.isInternalWorkspaceEntry($0) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    static func isInternalWorkspaceEntry(_ entry: CoworkFSEntry) -> Bool {
        entry.name == ".aionrs" || entry.name.hasPrefix(".aionrs/")
    }

    var workspaceDisplayPath: String {
        if let user = activeConversation?.workspacePath ?? (workspacePath.isEmpty ? nil : workspacePath) {
            return user
        }
        return L10n.agentSessionFolder
    }

    func openWorkspaceEntry(_ entry: CoworkFSEntry) async {
        guard let conversationID = activeConversationID else { return }
        if Self.isInternalWorkspaceEntry(entry) { return }
        if entry.isDirectory {
            workspaceRelativePath = workspaceRelativePath == "." ? entry.name : "\(workspaceRelativePath)/\(entry.name)"
            await refreshWorkspace()
            return
        }
        let workspace = activeConversation?.workspacePath ?? workspacePath
        let fullPath = workspaceRelativePath == "."
            ? entry.name
            : "\(workspaceRelativePath)/\(entry.name)"
        await openPreview(path: fullPath, workspace: workspace.isEmpty ? nil : workspace, title: entry.name)
    }

    func workspaceGoUp() async {
        guard workspaceRelativePath != "." else { return }
        if !workspaceRelativePath.contains("/") {
            workspaceRelativePath = "."
        } else {
            workspaceRelativePath = String(workspaceRelativePath.split(separator: "/").dropLast().joined(separator: "/"))
            if workspaceRelativePath.isEmpty { workspaceRelativePath = "." }
        }
        await refreshWorkspace()
    }

    func openPreview(path: String, workspace: String?, title: String) async {
        let resolvedWorkspace = workspace.flatMap { $0.isEmpty ? nil : $0 }
            ?? (workspacePath.isEmpty ? nil : workspacePath)
        let absolutePath = CoworkWorkspaceFileAccess.resolveAbsolutePath(relativePath: path, workspace: resolvedWorkspace)
        let ext = (absolutePath as NSString).pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "svg"]
        let textExtensions = ["md", "markdown", "txt", "json", "swift", "py", "js", "ts", "html", "css", "sh", "yml", "yaml", "xml", "csv"]
        let documentExtensions = ["docx", "doc", "rtf"]

        do {
            if imageExtensions.contains(ext) {
                var b64 = CoworkWorkspaceFileAccess.readBase64(at: absolutePath)
                if b64 == nil, let client {
                    b64 = try await client.readImageBase64(path: path, workspace: resolvedWorkspace)
                }
                guard let b64 else {
                    statusMessage = L10n.imagePreviewFailed
                    return
                }
                upsertPreview(CoworkPreviewItem(
                    id: absolutePath,
                    title: title,
                    path: absolutePath,
                    content: "",
                    contentType: .image,
                    imageBase64: b64
                ))
                return
            }

            if ext == "pdf" {
                var b64 = CoworkWorkspaceFileAccess.readBase64(at: absolutePath)
                if b64 == nil, let client {
                    b64 = try await client.readFileBuffer(path: path, workspace: resolvedWorkspace)
                }
                guard let b64 else {
                    statusMessage = L10n.pdfPreviewFailed
                    return
                }
                upsertPreview(CoworkPreviewItem(
                    id: absolutePath,
                    title: title,
                    path: absolutePath,
                    content: b64,
                    contentType: .pdf,
                    imageBase64: nil
                ))
                return
            }

            if documentExtensions.contains(ext) {
                if let text = CoworkWorkspaceFileAccess.readText(at: absolutePath), !text.isEmpty {
                    upsertPreview(CoworkPreviewItem(
                        id: absolutePath,
                        title: title,
                        path: absolutePath,
                        content: text,
                        contentType: .text,
                        imageBase64: nil
                    ))
                } else {
                    statusMessage = L10n.pdfPreviewFailed
                }
                return
            }

            var text = CoworkWorkspaceFileAccess.readText(at: absolutePath)
            if text == nil, let client {
                text = try await client.readFile(path: path, workspace: resolvedWorkspace)
            }
            let body = text ?? ""
            let type: CoworkPreviewContentType
            if ext == "html" || ext == "htm" { type = .html }
            else if ext == "md" || ext == "markdown" { type = .markdown }
            else if textExtensions.contains(ext) { type = .code }
            else { type = .text }

            upsertPreview(CoworkPreviewItem(id: absolutePath, title: title, path: absolutePath, content: body, contentType: type, imageBase64: nil))
        } catch {
            if let local = CoworkWorkspaceFileAccess.readText(at: absolutePath), !local.isEmpty {
                upsertPreview(CoworkPreviewItem(
                    id: absolutePath,
                    title: title,
                    path: absolutePath,
                    content: local,
                    contentType: .text,
                    imageBase64: nil
                ))
            } else {
                statusMessage = error.localizedDescription
            }
        }
    }

    func openDiffPreview(path: String) async {
        guard let client, let workspace = activeConversation?.workspacePath else { return }
        do {
            let filePath = path
            let current = try await client.readFile(path: filePath, workspace: workspace) ?? ""
            let baseline = try await client.snapshotBaseline(workspace: workspace, filePath: filePath) ?? ""
            upsertPreview(CoworkPreviewItem(
                id: "diff-\(filePath)",
                title: L10n.diffTitle((filePath as NSString).lastPathComponent),
                path: filePath,
                content: current,
                contentType: .diff,
                imageBase64: nil,
                diffOldText: baseline
            ))
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    func refreshConfirmations(for conversationID: String? = nil) async {
        guard let client else { return }
        let targetID = conversationID
            ?? activeConversationID
            ?? activeConfirmation?.conversationID
            ?? pendingConfirmations.first?.conversationID
            ?? confirmationAnchorConversationID
        guard let targetID else { return }
        do {
            let listed = try await client.listConfirmations(conversationID: targetID)
            let anchored = listed.map { $0.withConversationID(targetID) }
            pendingConfirmations = anchored
            if let active = activeConfirmation,
               anchored.contains(where: { $0.callID == active.callID }) {
                activeConfirmation = anchored.first(where: { $0.callID == active.callID }) ?? anchored.first
            } else if activeConfirmation == nil {
                activeConfirmation = anchored.first
            } else if anchored.isEmpty {
                activeConfirmation = nil
            }
            if !anchored.isEmpty {
                confirmationAnchorConversationID = targetID
            } else if confirmationAnchorConversationID == targetID {
                confirmationAnchorConversationID = nil
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func respondToConfirmation(option: CoworkConfirmationOption, alwaysAllow: Bool = false) async {
        guard let client, let confirmation = activeConfirmation else { return }
        let conversationID = confirmation.conversationID
            ?? activeConversationID
            ?? confirmationAnchorConversationID
        guard let conversationID else {
            statusMessage = L10n.permissionSessionMissing
            return
        }
        let msgID = confirmation.msgID ?? confirmation.id
        do {
            try await client.confirmAction(
                conversationID: conversationID,
                callID: confirmation.callID,
                msgID: msgID,
                confirmKey: option.value,
                alwaysAllow: alwaysAllow
            )
            pendingConfirmations.removeAll { $0.callID == confirmation.callID }
            activeConfirmation = pendingConfirmations.first
            if pendingConfirmations.isEmpty {
                confirmationAnchorConversationID = activeConversationID
            }
            // Resume streaming indicator if the turn is still live after Allow.
            if activeTurnID != nil {
                isStreaming = true
            }
            await refreshConfirmations(for: conversationID)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Opens the session that owns the active permission prompt (from the global card).
    func openConfirmationConversation() async {
        let id = activeConfirmation?.conversationID
            ?? pendingConfirmations.first?.conversationID
            ?? confirmationAnchorConversationID
        guard let id else { return }
        await openConversation(id)
    }

    func onTurnCompleted() async {
        isStreaming = false
        activeTurnID = nil
        if let conversationID = activeConversationID {
            await loadMessages(for: conversationID)
            await refreshWorkspace()
            await refreshConfirmations(for: conversationID)
            await refreshFileChanges()
        } else if let anchor = confirmationAnchorConversationID {
            await refreshConfirmations(for: anchor)
        }
        if let next = pendingCommands.first {
            pendingCommands.removeFirst()
            await sendInConversation(next)
        } else {
            requestComposerFocus()
        }
    }

    private func upsertPreview(_ item: CoworkPreviewItem) {
        if let idx = previewItems.firstIndex(where: { $0.id == item.id }) {
            previewItems[idx] = item
        } else {
            previewItems.append(item)
        }
        selectedPreviewID = item.id
    }

    private func handleConfirmationEvent(_ data: Data) {
        guard var confirmation = CoworkConfirmation.decodeFlexible(from: data) else { return }
        let anchor = confirmation.conversationID
            ?? activeConversationID
            ?? confirmationAnchorConversationID
        confirmation = confirmation.withConversationID(anchor)
        if let anchor {
            confirmationAnchorConversationID = anchor
        }
        if let idx = pendingConfirmations.firstIndex(where: { $0.callID == confirmation.callID }) {
            pendingConfirmations[idx] = confirmation
        } else {
            pendingConfirmations.append(confirmation)
        }
        activeConfirmation = confirmation
        // Permission wait is still an in-flight agent turn.
        isStreaming = true
        CitadelDeskCompanionController.shared.showConfirmPulse()
    }

    private func handleConfirmationRemoved(_ data: Data) {
        struct RemovePayload: Decodable {
            let id: String?
            let callID: String?
            enum CodingKeys: String, CodingKey {
                case id
                case callID = "call_id"
                case callId
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decodeIfPresent(String.self, forKey: .id)
                callID = try c.decodeIfPresent(String.self, forKey: .callID)
                    ?? c.decodeIfPresent(String.self, forKey: .callId)
            }
        }
        guard let payload = try? JSONDecoder.cowork.decode(RemovePayload.self, from: data) else { return }
        let key = payload.callID ?? payload.id
        guard let key else { return }
        pendingConfirmations.removeAll { $0.callID == key || $0.id == key }
        if activeConfirmation?.callID == key || activeConfirmation?.id == key {
            activeConfirmation = pendingConfirmations.first
        }
        if pendingConfirmations.isEmpty, activeConversationID == nil {
            confirmationAnchorConversationID = nil
        }
    }

    private func handlePreviewOpen(_ data: Data) {
        guard let event = try? JSONDecoder.cowork.decode(CoworkPreviewOpenEvent.self, from: data) else { return }
        let title = event.metadata?.title ?? event.metadata?.fileName ?? "Preview"
        let content = event.content ?? ""
        let type = CoworkPreviewContentType(rawValue: event.contentType ?? "text") ?? .text
        let id = event.metadata?.fileName ?? UUID().uuidString
        upsertPreview(CoworkPreviewItem(id: id, title: title, path: nil, content: content, contentType: type, imageBase64: nil))
    }

    private func applyStream(_ message: CoworkWSResponseMessage) {
        guard let msgID = message.msgID else { return }
        let belongsToActive = message.conversationID == activeConversationID
        let anchorID = confirmationAnchorConversationID
            ?? activeConfirmation?.conversationID
            ?? pendingConfirmations.first?.conversationID
        let belongsToBackgroundAnchor = activeConversationID == nil
            && message.conversationID != nil
            && message.conversationID == anchorID

        // Chat closed but turn still waiting on permissions — keep confirmation queue in sync.
        if belongsToBackgroundAnchor && !belongsToActive {
            switch message.type {
            case "start", "tool_group", "tool_call", "acp_tool_call":
                isStreaming = true
                if message.type != "start" {
                    Task { @MainActor [weak self] in
                        await self?.refreshConfirmations(for: message.conversationID)
                    }
                }
            case "finish":
                Task { @MainActor [weak self] in
                    await self?.refreshConfirmations(for: message.conversationID)
                }
            default:
                break
            }
            return
        }

        guard belongsToActive else { return }

        switch message.type {
        case "start":
            streamCoalescer.reset(msgID: msgID)
            resetAnswerTypewriter(msgID: msgID)
            isStreaming = true
            thinkingParsers[msgID] = CoworkThinkingTagStreamParser(
                supportsImplicitLeadingThinking: false
            )
            liveStreamSegments[msgID] = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
        case "content", "text":
            guard let chunk = message.textChunk, !chunk.isEmpty else { return }
            if message.replace == true {
                streamCoalescer.reset(msgID: msgID)
                resetAnswerTypewriter(msgID: msgID)
                thinkingParsers[msgID] = CoworkThinkingTagStreamParser(
                    supportsImplicitLeadingThinking: false
                )
                liveStreamSegments[msgID] = CoworkLiveStreamSegment()
            }
            streamCoalescer.enqueue(
                msgID: msgID,
                piece: chunk,
                preferFastFlush: shouldPreferFastStreamFlush(msgID: msgID)
            ) { [weak self] merged in
                self?.applyStreamTextChunk(msgID: msgID, chunk: merged)
            }
            isStreaming = true
        case "tool_group", "tool_call", "acp_tool_call":
            guard let data = message.data else { return }
            let calls = CoworkToolCallNormalizer.normalize(
                streamType: message.type ?? "tool_call",
                msgID: msgID,
                json: data
            )
            guard !calls.isEmpty else { return }
            if liveToolCalls[msgID] == nil {
                liveToolOrder.append(msgID)
            }
            var merged = message.replace == true ? [] : (liveToolCalls[msgID] ?? [])
            for call in calls {
                if let idx = merged.firstIndex(where: { $0.id == call.id }) {
                    merged[idx] = call
                } else {
                    merged.append(call)
                }
            }
            liveToolCalls[msgID] = merged
            streamTick += 1
            isStreaming = true
            // Tool prompts often arrive as stream tool_call before/without a clean WS confirmation.add.
            // Resync the REST confirmation queue so the permission card appears during the first turn.
            if calls.contains(where: { $0.status == .pending || $0.status == .running }) {
                let conversationID = message.conversationID ?? activeConversationID
                Task { @MainActor [weak self] in
                    await self?.refreshConfirmations(for: conversationID)
                }
            }
        case "finish":
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.streamCoalescer.flush(msgID: msgID) { merged in
                    self.applyStreamTextChunk(msgID: msgID, chunk: merged)
                }
                self.completeStreamFinish(msgID: msgID, message: message)
            }
        default:
            break
        }
    }

    private func applyStreamTextChunk(msgID: String, chunk: String) {
        guard !chunk.isEmpty else { return }
        var parser = thinkingParsers[msgID] ?? CoworkThinkingTagStreamParser(
            supportsImplicitLeadingThinking: false
        )
        let parsed = parser.process(chunk)
        thinkingParsers[msgID] = parser

        guard !parsed.answer.isEmpty
            || !parsed.thinking.isEmpty
            || parsed.didStartThinking
            || parsed.didFinishThinking
        else { return }

        var segment = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
        // Append immediately (Murmura). Per-glyph typewriter + full markdown reparse made 27B feel like 10s/word.
        if !parsed.thinking.isEmpty {
            segment.thinking += parsed.thinking
        }
        if !parsed.answer.isEmpty {
            segment.answer += parsed.answer
        }
        if parsed.didStartThinking {
            segment.isThinkingActive = true
            segment.thinkingFinishedAt = nil
        }
        if parsed.didFinishThinking {
            segment.isThinkingActive = false
            segment.thinkingFinishedAt = Date()
        } else if !segment.thinking.isEmpty && segment.answer.isEmpty {
            segment.isThinkingActive = true
            segment.thinkingFinishedAt = nil
        }
        liveStreamSegments[msgID] = segment
        let urgent = !parsed.answer.isEmpty || parsed.didFinishThinking || parsed.didStartThinking
        publishStreamUI(urgent: urgent)
    }

    private func publishStreamUI(urgent: Bool) {
        let now = Date()
        if urgent || now.timeIntervalSince(lastStreamUIPublish) >= 0.08 {
            streamUIFlushTask?.cancel()
            streamUIFlushTask = nil
            lastStreamUIPublish = now
            streamTick += 1
            return
        }
        guard streamUIFlushTask == nil else { return }
        streamUIFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, !Task.isCancelled else { return }
            self.lastStreamUIPublish = Date()
            self.streamTick += 1
            self.streamUIFlushTask = nil
        }
    }

    func clearLiveStreamSegments() {
        liveStreamSegments = [:]
        streamUIFlushTask?.cancel()
        streamUIFlushTask = nil
        streamTick += 1
    }

    private func enqueueAnswerTypewriter(msgID: String, piece: String) {
        guard !piece.isEmpty else { return }
        var segment = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
        segment.answer += piece
        if segment.isThinkingActive {
            segment.isThinkingActive = false
            segment.thinkingFinishedAt = segment.thinkingFinishedAt ?? Date()
        }
        liveStreamSegments[msgID] = segment
        publishStreamUI(urgent: true)
    }

    private func flushAnswerTypewriter(msgID: String) {
        answerTypewriterTasks[msgID]?.cancel()
        answerTypewriterTasks[msgID] = nil
        guard let remainder = answerTypewriterQueues.removeValue(forKey: msgID), !remainder.isEmpty else { return }
        var segment = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
        segment.answer += remainder
        liveStreamSegments[msgID] = segment
        publishStreamUI(urgent: true)
    }

    func resetAnswerTypewriter(msgID: String) {
        answerTypewriterTasks[msgID]?.cancel()
        answerTypewriterTasks.removeValue(forKey: msgID)
        answerTypewriterQueues.removeValue(forKey: msgID)
    }

    func resetAnswerTypewriters() {
        for task in answerTypewriterTasks.values {
            task.cancel()
        }
        answerTypewriterTasks.removeAll()
        answerTypewriterQueues.removeAll()
    }

    private func shouldPreferFastStreamFlush(msgID: String) -> Bool {
        guard let segment = liveStreamSegments[msgID] else { return true }
        if segment.isThinkingActive { return true }
        if !segment.thinking.isEmpty && segment.answer.isEmpty { return true }
        return false
    }

    private func archiveThinkingIfNeeded(msgID: String) {
        guard let segment = liveStreamSegments[msgID] else { return }
        let trimmed = segment.thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        archivedThinkingByMsgID[msgID] = CoworkArchivedThinking(
            text: trimmed,
            finishedAt: segment.thinkingFinishedAt ?? Date(),
            cardExpanded: segment.thinkingCardExpanded
        )
    }

    private func completeStreamFinish(msgID: String, message: CoworkWSResponseMessage) {
        captureTokenUsage(from: message)
        if var parser = thinkingParsers[msgID] {
            let remainder = parser.flush()
            thinkingParsers.removeValue(forKey: msgID)
            if !remainder.thinking.isEmpty {
                var segment = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
                segment.thinking += remainder.thinking
                if segment.isThinkingActive {
                    segment.isThinkingActive = false
                    segment.thinkingFinishedAt = Date()
                }
                liveStreamSegments[msgID] = segment
            }
            if !remainder.answer.isEmpty {
                enqueueAnswerTypewriter(msgID: msgID, piece: remainder.answer)
            }
        }
        // Ensure any pending typewriter chars land before we mark the turn finished.
        flushAnswerTypewriter(msgID: msgID)
        if var segment = liveStreamSegments[msgID], segment.isThinkingActive {
            segment.isThinkingActive = false
            segment.thinkingFinishedAt = Date()
            liveStreamSegments[msgID] = segment
        }
        archiveThinkingIfNeeded(msgID: msgID)
        streamCoalescer.reset(msgID: msgID)
        isStreaming = false
        if let conversationID = activeConversationID {
            Task {
                await loadMessages(for: conversationID)
                liveStreamSegments.removeValue(forKey: msgID)
                thinkingParsers.removeValue(forKey: msgID)
                resetAnswerTypewriter(msgID: msgID)
                requestComposerFocus()
            }
        } else {
            requestComposerFocus()
        }
    }
}
