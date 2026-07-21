import Foundation

@MainActor
extension CoworkState {
    // MARK: - Sprint A

    func resetActiveConversation(keepWorkspace: Bool = true) async {
        guard let client, let id = activeConversationID else { return }
        do {
            try await client.resetConversation(id: id, keepWorkspace: keepWorkspace)
            messages = []
            liveStreamSegments = [:]
            thinkingParsers = [:]
            lastTokenUsage = nil
            conversationUsage = CoworkConversationUsageStats()
            await loadMessages(for: id)
            await refreshWorkspace()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func forkActiveConversation() async {
        guard let client, let conversation = activeConversation else { return }
        do {
            let payload = CoworkConversationClonePayload(
                id: conversation.id,
                name: (conversation.name ?? L10n.session) + " (fork)",
                type: conversation.type,
                model: conversation.model,
                extra: conversation.extra
            )
            let forked = try await client.cloneConversation(payload)
            conversations.insert(forked, at: 0)
            await openConversation(forked.id)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func applyPermissionModeToActiveConversation() async {
        guard let client, let conversationID = activeConversationID else { return }
        do {
            let updated = try await client.updateConversation(
                id: conversationID,
                CoworkUpdateConversationRequest(
                    extra: CoworkConversationExtra(permission: agentPermissionMode),
                    mergeExtra: true
                )
            )
            activeConversation = updated
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func applySkillsToActiveConversation() async {
        guard let client, let conversationID = activeConversationID else { return }
        guard activeModelSupportsTools else { return }
        do {
            let updated = try await client.updateConversation(
                id: conversationID,
                CoworkUpdateConversationRequest(
                    extra: CoworkConversationExtra(skillIDs: effectiveSkillIDs),
                    mergeExtra: true
                )
            )
            activeConversation = updated
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func searchActiveMessages() async {
        guard let client, let conversationID = activeConversationID else { return }
        let query = messageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            messageSearchResults = []
            return
        }
        do {
            messageSearchResults = try await client.searchMessages(conversationID: conversationID, query: query)
        } catch {
            statusMessage = error.localizedDescription
            messageSearchResults = []
        }
    }

    func captureTokenUsage(from message: CoworkWSResponseMessage) {
        if let usage = CoworkTokenUsage.parse(from: message.data) {
            lastTokenUsage = usage
            let model = activeConversation?.model?.model ?? selectedModelID
            let provider = activeModelDisplay.provider
            conversationUsage.record(usage: usage, model: model, provider: provider.isEmpty ? nil : provider)
            guard let client, let conversationID = activeConversationID else { return }
            Task {
                _ = try? await client.updateConversation(
                    id: conversationID,
                    CoworkUpdateConversationRequest(
                        extra: CoworkConversationExtra(lastTokenUsage: usage.totalTokens),
                        mergeExtra: true
                    )
                )
            }
        }
    }

    // MARK: - Sprint B

    func stageFileChange(_ change: CoworkFileChange) async {
        guard let client, let workspace = activeConversation?.workspacePath else { return }
        do {
            try await client.stageSnapshotFile(workspace: workspace, filePath: change.filePath)
            await refreshFileChanges()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func discardFileChange(_ change: CoworkFileChange) async {
        await discardFileChanges(paths: [change.filePath])
    }

    func discardFileChanges(paths: [String]? = nil) async {
        guard let client, let workspace = activeConversation?.workspacePath else { return }
        do {
            try await client.discardSnapshot(workspace: workspace, filePaths: paths)
            await refreshFileChanges()
            await refreshWorkspace()
        } catch { statusMessage = error.localizedDescription }
    }

    func stageAllFileChanges() async {
        guard let client, let workspace = activeConversation?.workspacePath else { return }
        do {
            try await client.stageAllSnapshot(workspace: workspace)
            await refreshFileChanges()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    /// Writes edited preview content back to disk through CoworkCore.
    func saveFileFromPreview(_ item: CoworkPreviewItem, content: String) async {
        guard let client, let path = item.path else { return }
        let workspace = activeConversation?.workspacePath
        do {
            try await client.writeFile(path: path, data: content, workspace: workspace)
            if let idx = previewItems.firstIndex(where: { $0.id == item.id }) {
                previewItems[idx].content = content
            }
            statusMessage = nil
            await refreshFileChanges()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func resetWorkspaceSnapshot() async {
        guard let client, let workspace = activeConversation?.workspacePath else { return }
        do {
            try await client.resetSnapshot(workspace: workspace)
            await refreshFileChanges()
        } catch { statusMessage = error.localizedDescription }
    }

    func renameWorkspaceFile(path: String, newName: String) async {
        guard let client else { return }
        let workspace = activeConversation?.workspacePath
        do {
            _ = try await client.renameWorkspaceEntry(path: path, newName: newName, workspace: workspace)
            await refreshWorkspace()
        } catch { statusMessage = error.localizedDescription }
    }

    func deleteWorkspaceFile(path: String) async {
        guard let client else { return }
        let workspace = activeConversation?.workspacePath
        do {
            try await client.removeWorkspaceEntry(path: path, workspace: workspace)
            await refreshWorkspace()
        } catch { statusMessage = error.localizedDescription }
    }

    // MARK: - Sprint C

    // MARK: - Assistants

    func createAssistant(name: String, description: String, rules: String, recommendedPrompts: [String] = []) async {
        guard let client else { return }
        let locale = CitadelLocale.current.rawValue
        do {
            let created = try await client.createAssistant(
                CoworkCreateAssistantRequest(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    recommendedPrompts: recommendedPrompts.isEmpty ? nil : recommendedPrompts
                )
            )
            try await persistAssistantRules(assistantID: created.id, content: rules, locale: locale, client: client)
            assistants = try await client.listAssistants()
            selectedAssistantID = created.id
            statusMessage = nil
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func deleteAssistant(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteAssistant(id: id)
            if selectedAssistantID == id { selectedAssistantID = "cowork" }
            assistants = try await client.listAssistants()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func loadAssistantDetail(_ id: String) async -> CoworkAssistantDetail? {
        guard let client else { return nil }
        let locale = CitadelLocale.current.rawValue
        do { return try await client.getAssistant(id: id, locale: locale) }
        catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
            return nil
        }
    }

    func saveAssistant(
        id: String,
        source: String?,
        name: String,
        description: String,
        rules: String,
        recommendedPrompts: [String],
        enabled: Bool
    ) async {
        guard let client else { return }
        let locale = CitadelLocale.current.rawValue
        let isBuiltin = source == "builtin"
        let isGenerated = source == "generated"

        do {
            if isGenerated {
                _ = try await client.updateAssistant(
                    id: id,
                    CoworkUpdateAssistantRequest(
                        description: description.isEmpty ? nil : description,
                        recommendedPrompts: recommendedPrompts.isEmpty ? nil : recommendedPrompts
                    )
                )
            } else if !isBuiltin {
                _ = try await client.updateAssistant(
                    id: id,
                    CoworkUpdateAssistantRequest(
                        name: name,
                        description: description.isEmpty ? nil : description,
                        recommendedPrompts: recommendedPrompts.isEmpty ? nil : recommendedPrompts
                    )
                )
            }

            if !isBuiltin {
                try await persistAssistantRules(assistantID: id, content: rules, locale: locale, client: client)
            }

            _ = try await client.setAssistantState(id: id, enabled: enabled)
            assistants = try await client.listAssistants()
            statusMessage = nil
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    private func persistAssistantRules(
        assistantID: String,
        content: String,
        locale: String,
        client: CoworkCoreClient
    ) async throws {
        let cleaned = CoworkUserFacing.sanitizeFreeText(content)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try await client.deleteAssistantRule(assistantID: assistantID)
        } else {
            try await client.writeAssistantRule(assistantID: assistantID, content: cleaned, locale: locale)
        }
    }

    /// Reads a builtin skill's markdown from CoworkCore (tries the skill file name, then the path's file name).
    func loadBuiltinSkillContent(_ skill: CoworkSkill) async -> String {
        guard let client else { return "" }
        var candidates = [skill.name]
        if let path = skill.path {
            let fileName = (path as NSString).lastPathComponent
            if !fileName.isEmpty { candidates.append(fileName) }
        }
        candidates.append(skill.name + ".md")
        for candidate in candidates {
            if let content = try? await client.readBuiltinSkill(fileName: candidate), !content.isEmpty {
                return CoworkUserFacing.skillContentDisplay(content)
            }
        }
        if let description = skill.displayDetail, !description.isEmpty {
            return description
        }
        return ""
    }

    func loadAssistantRule(assistantID: String) async -> String {
        guard let client else { return "" }
        let locale = CitadelLocale.current.rawValue
        do {
            let raw = try await client.readAssistantRule(assistantID: assistantID, locale: locale)
            let cleaned = CoworkUserFacing.sanitizeFreeText(raw)
            // Persist debranded copy so upstream AionUi wording does not reappear.
            if cleaned != raw {
                try? await persistAssistantRules(
                    assistantID: assistantID,
                    content: cleaned,
                    locale: locale,
                    client: client
                )
            }
            return cleaned
        } catch { return "" }
    }

    func saveAssistantRule(assistantID: String, content: String) async {
        guard let client else { return }
        let locale = CitadelLocale.current.rawValue
        let cleaned = CoworkUserFacing.sanitizeFreeText(content)
        do {
            try await persistAssistantRules(assistantID: assistantID, content: cleaned, locale: locale, client: client)
            statusMessage = nil
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func refreshManagedAgents() async {
        guard let client else { return }
        do { managedAgents = try await client.listManagedAgents() }
        catch { managedAgents = [] }
    }

    /// Backend-driven ACP discovery: rescan $PATH then reload the catalog.
    func rescanInstalledAgents() async {
        guard let client else { return }
        isScanningAgents = true
        defer { isScanningAgents = false }
        do {
            try await client.refreshAgentCatalog()
            managedAgents = try await client.listManagedAgents()
            let found = managedAgents.filter(\.isInstalled).count
            statusMessage = L10n.agentsDetected(found)
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    /// Tests a custom agent command (spawn + ACP handshake) without persisting it.
    func tryConnectCustomAgent(name: String, command: String) async -> Bool {
        guard let client else { return false }
        do {
            let result = try await client.tryConnectCustomAgent(CoworkCustomAgentRequest(name: name, command: command))
            statusMessage = result.detail ?? (result.connected ? L10n.agentHealthy : L10n.agentUnhealthy)
            return result.connected
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
            return false
        }
    }

    func healthCheckAgent(_ id: String) async {
        guard let client else { return }
        checkingAgentIDs.insert(id)
        defer { checkingAgentIDs.remove(id) }
        do {
            let result = try await client.agentHealthCheck(id: id)
            if let idx = managedAgents.firstIndex(where: { $0.id == id }) {
                managedAgents[idx] = result
            }
            statusMessage = "\(result.displayName): \(result.healthSummary)"
            await refreshManagedAgents()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    func setAgentEnabled(_ id: String, enabled: Bool) async {
        guard let client else { return }
        do {
            try await client.setAgentEnabled(id: id, enabled: enabled)
            await refreshManagedAgents()
        } catch { statusMessage = error.localizedDescription }
    }

    func connectCustomAgent(name: String, command: String) async {
        guard let client else { return }
        do {
            _ = try await client.connectCustomAgent(CoworkCustomAgentRequest(name: name, command: command))
            await refreshManagedAgents()
        } catch { statusMessage = error.localizedDescription }
    }

    func refreshMcpOAuth() async {
        guard let client else { return }
        do { mcpOAuthServers = try await client.mcpOAuthAuthenticatedServers() }
        catch { mcpOAuthServers = [] }
    }

    func mcpOAuthLogin(serverURL: String) async {
        guard let client else { return }
        do {
            let result = try await client.mcpOAuthLogin(serverURL: serverURL)
            if result.success {
                await refreshMcpOAuth()
            } else {
                statusMessage = result.error ?? L10n.oauthLoginFailed
            }
        } catch { statusMessage = error.localizedDescription }
    }

    func mcpOAuthLogout(serverURL: String) async {
        guard let client else { return }
        do {
            try await client.mcpOAuthLogout(serverURL: serverURL)
            await refreshMcpOAuth()
        } catch { statusMessage = error.localizedDescription }
    }

    // MARK: - Sprint D

    func refreshCronJobs() async {
        guard let client else { return }
        do { cronJobs = try await client.listCronJobs() }
        catch { cronJobs = [] }
    }

    func createCronJob(name: String, expr: String, prompt: String) async {
        guard let client else { return }
        do {
            let job = try await client.createCronJob(
                CoworkCreateCronJobRequest(
                    name: name,
                    enabled: true,
                    schedule: CoworkCronSchedule(kind: "cron", expr: expr, description: expr),
                    prompt: prompt,
                    assistantID: selectedAssistantID
                )
            )
            cronJobs.insert(job, at: 0)
        } catch { statusMessage = error.localizedDescription }
    }

    func updateCronJobDetails(id: String, name: String, expr: String, prompt: String) async {
        guard let client else { return }
        do {
            let updated = try await client.updateCronJob(
                id: id,
                CoworkUpdateCronJobRequest(
                    name: name,
                    schedule: CoworkCronSchedule(kind: "cron", expr: expr, description: expr),
                    prompt: prompt
                )
            )
            if let idx = cronJobs.firstIndex(where: { $0.id == id }) {
                cronJobs[idx] = updated
            }
        } catch { statusMessage = error.localizedDescription }
    }

    func setCronJobEnabled(_ id: String, enabled: Bool) async {
        guard let client else { return }
        do {
            let updated = try await client.updateCronJob(id: id, CoworkUpdateCronJobRequest(enabled: enabled))
            if let idx = cronJobs.firstIndex(where: { $0.id == id }) {
                cronJobs[idx] = updated
            }
        } catch { statusMessage = error.localizedDescription }
    }

    func runCronJob(_ id: String) async {
        guard let client else { return }
        do {
            let result = try await client.runCronJobNow(id: id)
            if let conversationID = result.conversationID {
                await openConversation(conversationID)
            }
        } catch { statusMessage = error.localizedDescription }
    }

    func deleteCronJob(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteCronJob(id: id)
            cronJobs.removeAll { $0.id == id }
        } catch { statusMessage = error.localizedDescription }
    }
}
