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
    @Published var liveStreamSegments: [String: CoworkLiveStreamSegment] = [:]
    /// Tool calls streamed live over WebSocket, keyed by msg_id (rendered before the persisted message exists).
    @Published var liveToolCalls: [String: [CoworkNormalizedToolCall]] = [:]
    @Published var liveToolOrder: [String] = []
    @Published private(set) var streamTick = 0

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
    @Published var showProviderSheet = false
    @Published var showProvidersManager = false
    @Published var showMcpSheet = false

    @Published var attachmentPaths: [String] = []
    @Published var composerAttachments: [String] = []
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
    let voiceScribe = CitadelVoiceScribe()

    let lifecycle = CoworkCoreLifecycle()
    private let webSocket = CoworkWebSocketClient()
    private var cancellables = Set<AnyCancellable>()
    private var webSocketHandlersRegistered = false
    var thinkingParsers: [String: CoworkThinkingTagStreamParser] = [:]

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
    }

    var client: CoworkCoreClient? {
        guard let port = corePort, coreStatus == .running else { return nil }
        return CoworkCoreClient(port: port)
    }

    var selectedProvider: CoworkProvider? {
        guard let selectedProviderID else { return providers.first }
        return providers.first { $0.id == selectedProviderID } ?? providers.first
    }

    var selectedAssistant: CoworkAssistant? {
        assistants.first { $0.id == selectedAssistantID }
            ?? assistants.first { $0.id == "cowork" }
            ?? assistants.first
    }

    /// Model the home composer will send with (respects Ollama vs MLX backend preference).
    var resolvedHomeModelID: String? {
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
        if let existing = providers.first(where: { $0.models.contains(model) }) {
            selectedProviderID = existing.id
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
        guard preferredLocalBackend == .mlx, let repoID = resolvedHomeModelID else { return }
        guard await CoworkMLXHubSnapshot.localSnapshotDirectory(repoID: repoID) != nil else { return }
        mlxRuntimeInstallMessage = L10n.mlxWarmingUp
        do {
            try await CoworkMLXServerBridge.startIfNeeded(repoID: repoID) { message in
                self.mlxRuntimeInstallMessage = message ?? L10n.mlxWarmingUp
            }
            try? await ensureCoreReady()
            try? await activateMLXModel(repoID)
            mlxRuntimeInstallMessage = nil
        } catch {
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
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

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
            if selectedMcpIDs.isEmpty {
                selectedMcpIDs = Set(mcpServers.filter { $0.enabled }.map(\.id))
            }

            if selectedProviderID == nil {
                selectedProviderID = providers.first?.id
                selectedModelID = providers.first?.models.first
            }
            if !assistants.contains(where: { $0.id == selectedAssistantID }),
               let cowork = assistants.first(where: { $0.id == "cowork" }) {
                selectedAssistantID = cowork.id
            }
            await bootstrapDefaultMcpIfNeeded()
            await refreshMcpAgentConfigs()
            await refreshOllamaModels()
            await refreshSkills()
            await refreshMLXModelsAsync()
            await syncLocalBackendSelection()
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

        // Home composer — follow the Ollama / MLX tab, not a stale provider id.
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

    var effectiveMcpIDs: [String] {
        activeModelSupportsTools ? Array(selectedMcpIDs) : []
    }

    var effectiveSkillIDs: [String] {
        activeModelSupportsTools ? Array(selectedSkillIDs) : []
    }

    var toolsDisabledNotice: String? {
        guard !activeModelSupportsTools, resolvedModelID != nil else { return nil }
        return L10n.chatOnlyModeNotice
    }

    /// Applies tool-capable or chat-only assistant snapshot so CoworkCore stops wiring tools for plain LLMs.
    func applyToolCapabilityProfile() async {
        guard let client, let conversationID = activeConversationID else { return }
        if availableSkills.isEmpty { await refreshSkills() }

        let assistantID = selectedAssistantID
        let locale = CitadelLocale.current.rawValue

        do {
            if activeModelSupportsTools {
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
                                mcpIDs: mcp.isEmpty ? nil : mcp,
                                skillIDs: skills.isEmpty ? nil : skills
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
                        )
                    )
                )
                activeConversation = updated
                statusMessage = nil
                try? await client.ensureRuntime(conversationID: conversationID)
            }
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
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

    var mlxRuntimeAvailable: Bool {
        CoworkMLXServerBridge.isMLXAvailable()
    }

    var supportsImplicitLeadingThinking: Bool {
        selectedModelID?.localizedCaseInsensitiveContains("qwen3.5") == true
    }

    func setThinkingCardExpanded(msgID: String, expanded: Bool) {
        guard var segment = liveStreamSegments[msgID] else { return }
        segment.thinkingCardExpanded = expanded
        liveStreamSegments[msgID] = segment
    }

    func closeConversation() {
        activeConversationID = nil
        activeConversation = nil
        messages = []
        liveStreamSegments = [:]
        liveToolCalls = [:]
        liveToolOrder = []
        thinkingParsers = [:]
        workspaceEntries = []
        previewItems = []
        selectedPreviewID = nil
        pendingConfirmations = []
        activeConfirmation = nil
        composerAttachments = []
        isStreaming = false
        activeTurnID = nil
        lastTokenUsage = nil
        conversationUsage = CoworkConversationUsageStats()
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
            messages = page.items
            hasMoreMessages = page.hasMore == true
            if !isStreaming {
                liveStreamSegments = [:]
                liveToolCalls = [:]
                liveToolOrder = []
                thinkingParsers = [:]
            }
            if let tip = page.items.last(where: { $0.isTips })?.errorMessage ?? page.items.last(where: { $0.isTips })?.textBody,
               !tip.isEmpty,
               !( !activeModelSupportsTools && Self.isStaleToolRejection(tip) ) {
                statusMessage = L10n.localizeError(tip)
            } else if !activeModelSupportsTools {
                statusMessage = nil
            }
        } catch {
            statusMessage = error.localizedDescription
        }
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

    func localizedStatus(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if !activeModelSupportsTools && Self.isStaleToolRejection(raw) { return nil }
        return L10n.statusLine(raw, chatOnly: !activeModelSupportsTools)
    }

    func sendFromHome() async {
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
        defer { isSending = false }

        do {
            try await ensureCoreReady()
        } catch {
            statusMessage = L10n.coreNotReady
            return
        }

        guard let client else {
            statusMessage = L10n.coreNotReady
            return
        }

        await syncLocalBackendSelection()

        if preferredLocalBackend == .mlx {
            let target = resolvedHomeModelID ?? ""
            do {
                try await ensureMLXReadyForSend(repoID: target)
            } catch CoworkMLXBridgeError.modelNotInstalled {
                statusMessage = L10n.mlxModelNotInstalled
                return
            } catch {
                statusMessage = L10n.localizeError(
                    CoworkMLXModelLibrary.enrichedLoadErrorMessage(error.localizedDescription)
                )
                return
            }
        }

        guard let provider = selectedProvider, let model = resolvedHomeModelID else {
            statusMessage = L10n.selectModelFirst
            return
        }
        guard let assistant = selectedAssistant else {
            statusMessage = L10n.noAssistant
            return
        }

        statusMessage = nil

        do {
            if availableSkills.isEmpty { await refreshSkills() }
            let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let mcpIDs = effectiveMcpIDs
            let skillIDs = effectiveSkillIDs
            let supportsTools = CoworkModelToolSupport.supportsTools(
                modelID: model,
                providerID: provider.id,
                providers: providers,
                ollamaModels: ollamaChatModels
            )
            let request = CoworkCreateConversationRequest(
                name: String(text.prefix(80)),
                model: CoworkProviderModelRef(providerID: provider.id, model: model),
                assistant: CoworkAssistantRef(
                    id: assistant.id,
                    locale: CitadelLocale.current.rawValue,
                    conversationOverrides: supportsTools
                        ? CoworkConversationOverrides(
                            model: model,
                            permission: agentPermissionMode,
                            mcpIDs: mcpIDs.isEmpty ? nil : mcpIDs,
                            skillIDs: skillIDs.isEmpty ? nil : skillIDs
                        )
                        : chatOnlyCreateOverrides(model: model)
                ),
                extra: supportsTools
                    ? CoworkConversationExtra(
                        workspace: workspace.isEmpty ? nil : workspace,
                        customWorkspace: !workspace.isEmpty,
                        defaultFiles: attachmentPaths.isEmpty ? nil : attachmentPaths,
                        selectedMcpServerIDs: mcpIDs.isEmpty ? nil : mcpIDs,
                        skillIDs: skillIDs.isEmpty ? nil : skillIDs
                    )
                    : chatOnlyCreateExtra(
                        workspace: workspace.isEmpty ? nil : workspace,
                        customWorkspace: !workspace.isEmpty,
                        defaultFiles: attachmentPaths.isEmpty ? nil : attachmentPaths
                    )
            )
            let conversation = try await client.createConversation(request)
            let files = attachmentPaths
            promptText = ""
            attachmentPaths = []
            await refreshConversations()
            activeConversationID = conversation.id
            activeConversation = conversation
            let result = try await client.sendMessage(conversationID: conversation.id, input: text, files: files)
            activeTurnID = result.turnID
            statusMessage = nil
            isStreaming = true
            await loadMessages(for: conversation.id)
            await refreshWorkspace()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    func sendInConversation(_ text: String) async {
        guard let client, let conversationID = activeConversationID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isSending || isStreaming {
            pendingCommands.append(trimmed)
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            await ensureConversationProvider()
            if preferredLocalBackend == .mlx, let mlxModel = resolvedHomeModelID {
                try await ensureMLXReadyForSend(repoID: mlxModel)
            }
            await applyToolCapabilityProfile()
            try? await client.ensureRuntime(conversationID: conversationID)
            let files = composerAttachments
            let result = try await client.sendMessage(conversationID: conversationID, input: trimmed, files: files)
            activeTurnID = result.turnID
            statusMessage = nil
            composerAttachments = []
            isStreaming = true
            await loadMessages(for: conversationID)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stopGeneration() async {
        guard let client, let conversationID = activeConversationID, let turnID = activeTurnID else { return }
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
            if selectedModelID == nil, let first = ollamaChatModels.first {
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
        guard let client else { return }
        if let existing = providers.first(where: { $0.models.contains(name) && $0.baseURL.contains("11434") }) {
            selectedProviderID = existing.id
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
    }

    func selectCloudModel(providerID: String, model: String) async {
        UserDefaults.standard.set(CoworkModelPickerTab.cloud.rawValue, forKey: "cowork.modelPickerTab")
        selectedProviderID = providerID
        selectedModelID = model
        statusMessage = nil
        if activeConversationID != nil {
            await switchActiveConversationModel(providerID: providerID, model: model)
        }
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
    func activateMLXModel(_ repoID: String) async throws {
        guard let client else { throw CoworkCoreError.notConnected }
        try await CoworkMLXServerBridge.startIfNeeded(repoID: repoID) { message in
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
            selectedProviderID = existing.id
            selectedModelID = repoID
            statusMessage = nil
            mlxRuntimeInstallMessage = nil
            return
        }
        try await addProvider(
            preset: .custom,
            name: "Native MLX",
            baseURL: normalized,
            apiKey: "mlx",
            modelID: repoID,
            resolvedBaseURL: normalized
        )
        statusMessage = nil
        mlxRuntimeInstallMessage = nil
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
            if !provider.models.isEmpty, selectedProviderID == nil {
                selectedProviderID = provider.id
                selectedModelID = provider.models.first
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
        }
    }

    enum AttachmentTarget { case home, composer }

    func removeAttachment(_ path: String, target: AttachmentTarget = .home) {
        switch target {
        case .home:
            attachmentPaths.removeAll { $0 == path }
        case .composer:
            composerAttachments.removeAll { $0 == path }
        }
    }

    func refreshMcpServers() async {
        guard let client else { return }
        do {
            mcpServers = try await client.listMcpServers()
            if selectedMcpIDs.isEmpty {
                selectedMcpIDs = Set(mcpServers.filter { $0.enabled }.map(\.id))
            } else {
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
        guard let client else { return }
        let absolutePath: String
        if let workspace, !workspace.isEmpty, !path.hasPrefix("/") {
            absolutePath = (workspace as NSString).appendingPathComponent(path)
        } else {
            absolutePath = path
        }
        let ext = (absolutePath as NSString).pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "svg"]
        let textExtensions = ["md", "markdown", "txt", "json", "swift", "py", "js", "ts", "html", "css", "sh", "yml", "yaml", "xml", "csv"]

        do {
            if imageExtensions.contains(ext) {
                let b64 = try await client.readImageBase64(path: path, workspace: workspace)
                let item = CoworkPreviewItem(
                    id: absolutePath,
                    title: title,
                    path: absolutePath,
                    content: "",
                    contentType: .image,
                    imageBase64: b64
                )
                upsertPreview(item)
                return
            }

            if ext == "pdf" {
                if let b64 = try await client.readFileBuffer(path: path, workspace: workspace) {
                    upsertPreview(CoworkPreviewItem(
                        id: absolutePath,
                        title: title,
                        path: absolutePath,
                        content: b64,
                        contentType: .pdf,
                        imageBase64: nil
                    ))
                }
                return
            }

            let text = try await client.readFile(path: path, workspace: workspace) ?? ""
            let type: CoworkPreviewContentType
            if ext == "html" || ext == "htm" { type = .html }
            else if ext == "md" || ext == "markdown" { type = .markdown }
            else if textExtensions.contains(ext) { type = .code }
            else { type = .text }

            upsertPreview(CoworkPreviewItem(id: absolutePath, title: title, path: absolutePath, content: text, contentType: type, imageBase64: nil))
        } catch {
            statusMessage = error.localizedDescription
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

    func refreshConfirmations() async {
        guard let client, let conversationID = activeConversationID else { return }
        do {
            pendingConfirmations = try await client.listConfirmations(conversationID: conversationID)
            if activeConfirmation == nil {
                activeConfirmation = pendingConfirmations.first
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func respondToConfirmation(option: CoworkConfirmationOption, alwaysAllow: Bool = false) async {
        guard let client, let confirmation = activeConfirmation,
              let conversationID = activeConversationID else { return }
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
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func onTurnCompleted() async {
        isStreaming = false
        activeTurnID = nil
        if let conversationID = activeConversationID {
            await loadMessages(for: conversationID)
            await refreshWorkspace()
            await refreshConfirmations()
            await refreshFileChanges()
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
        guard let confirmation = try? JSONDecoder.cowork.decode(CoworkConfirmation.self, from: data) else { return }
        if let idx = pendingConfirmations.firstIndex(where: { $0.callID == confirmation.callID }) {
            pendingConfirmations[idx] = confirmation
        } else {
            pendingConfirmations.append(confirmation)
        }
        activeConfirmation = confirmation
        CitadelDeskCompanionController.shared.showConfirmPulse()
    }

    private func handleConfirmationRemoved(_ data: Data) {
        struct RemovePayload: Decodable { let id: String?; let callID: String?; enum CodingKeys: String, CodingKey { case id; case callID = "call_id" } }
        guard let payload = try? JSONDecoder.cowork.decode(RemovePayload.self, from: data) else { return }
        let key = payload.callID ?? payload.id
        guard let key else { return }
        pendingConfirmations.removeAll { $0.callID == key || $0.id == key }
        if activeConfirmation?.callID == key { activeConfirmation = pendingConfirmations.first }
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
        guard message.conversationID == activeConversationID,
              let msgID = message.msgID else { return }

        switch message.type {
        case "start":
            isStreaming = true
            thinkingParsers[msgID] = CoworkThinkingTagStreamParser(
                supportsImplicitLeadingThinking: supportsImplicitLeadingThinking
            )
            liveStreamSegments[msgID] = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
        case "content", "text":
            guard let chunk = message.textChunk, !chunk.isEmpty else { return }
            if message.replace == true {
                thinkingParsers[msgID] = CoworkThinkingTagStreamParser(
                    supportsImplicitLeadingThinking: supportsImplicitLeadingThinking
                )
                liveStreamSegments[msgID] = CoworkLiveStreamSegment()
            }
            var parser = thinkingParsers[msgID] ?? CoworkThinkingTagStreamParser(
                supportsImplicitLeadingThinking: supportsImplicitLeadingThinking
            )
            let parsed = parser.process(chunk)
            thinkingParsers[msgID] = parser

            var segment = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
            if !parsed.answer.isEmpty {
                segment.answer += parsed.answer
            }
            if !parsed.thinking.isEmpty {
                segment.thinking += parsed.thinking
            }
            if parsed.didStartThinking {
                segment.isThinkingActive = true
                segment.thinkingFinishedAt = nil
            }
            if parsed.didFinishThinking {
                segment.isThinkingActive = false
                segment.thinkingFinishedAt = Date()
            }
            liveStreamSegments[msgID] = segment
            streamTick += 1
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
        case "finish":
            captureTokenUsage(from: message)
            if var parser = thinkingParsers[msgID] {
                let remainder = parser.flush()
                thinkingParsers.removeValue(forKey: msgID)
                var segment = liveStreamSegments[msgID] ?? CoworkLiveStreamSegment()
                if !remainder.answer.isEmpty { segment.answer += remainder.answer }
                if !remainder.thinking.isEmpty { segment.thinking += remainder.thinking }
                if segment.isThinkingActive {
                    segment.isThinkingActive = false
                    segment.thinkingFinishedAt = Date()
                }
                liveStreamSegments[msgID] = segment
            }
            isStreaming = false
            if let conversationID = activeConversationID {
                Task {
                    await loadMessages(for: conversationID)
                    liveStreamSegments.removeValue(forKey: msgID)
                    thinkingParsers.removeValue(forKey: msgID)
                    requestComposerFocus()
                }
            } else {
                requestComposerFocus()
            }
        default:
            break
        }
    }
}
