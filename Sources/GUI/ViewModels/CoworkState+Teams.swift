import Foundation

// MARK: - Teams orchestration (plan Phase 5)

struct CoworkTeamAssistantEligibility: Hashable, Sendable {
    let selectable: Bool
    let blockReason: String?
    let agentStatusMessage: String?
}

extension CoworkState {
    func refreshTeams() async {
        guard let client else { return }
        do { teams = try await client.listTeams() }
        catch { teams = [] }
    }

    /// Loads `team_selectable` / block reasons for every assistant (used by team pickers).
    func refreshTeamAssistantEligibility() async {
        guard let client else { return }
        let locale = CitadelLocale.current.rawValue
        let snapshot = assistants
        var map: [String: CoworkTeamAssistantEligibility] = [:]
        await withTaskGroup(of: (String, CoworkTeamAssistantEligibility?).self) { group in
            for assistant in snapshot {
                group.addTask {
                    guard let detail = try? await client.getAssistant(id: assistant.id, locale: locale) else {
                        return (assistant.id, nil)
                    }
                    let selectable = detail.teamSelectable ?? true
                    return (
                        assistant.id,
                        CoworkTeamAssistantEligibility(
                            selectable: selectable,
                            blockReason: detail.teamBlockReason,
                            agentStatusMessage: detail.agentStatusMessage
                        )
                    )
                }
            }
            for await (id, eligibility) in group {
                if let eligibility { map[id] = eligibility }
            }
        }
        teamAssistantEligibility = map
    }

    func isAssistantTeamSelectable(_ id: String) -> Bool {
        teamAssistantEligibility[id]?.selectable ?? true
    }

    func teamBlockReason(for id: String) -> String? {
        teamAssistantEligibility[id]?.blockReason
    }

    func assistantsEligibleForTeam(excluding ids: Set<String> = []) -> [CoworkAssistant] {
        assistants.filter { !ids.contains($0.id) && isAssistantTeamSelectable($0.id) }
    }

    func activeTeamAssistantIDs() -> Set<String> {
        Set(activeTeam?.assistants.compactMap(\.assistantID) ?? [])
    }

    func openTeam(_ id: String) async {
        guard let client else { return }
        let ownsBusy = !isTeamBusy
        if ownsBusy {
            isTeamBusy = true
            teamActivityMessage = L10n.teamOpening
        }
        defer {
            if ownsBusy {
                isTeamBusy = false
                teamActivityMessage = nil
            }
        }
        do {
            let team = try await client.getTeam(id: id)
            try await client.ensureTeamSession(teamID: id)
            try? await client.acquireTeamLease(teamID: id)
            activeTeamID = id
            activeTeam = team
            await refreshTeamRunState()
            await refreshTeamSlotFeeds()
        } catch {
            if activeTeamID == id { closeTeam() }
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    func closeTeam() {
        activeTeamID = nil
        activeTeam = nil
        teamRunState = nil
        teamSlotMessages = [:]
    }

    @discardableResult
    func createTeam(name: String, leaderAssistantID: String?, memberAssistantIDs: [String], workspace: String?) async -> Bool {
        guard let client else { return false }
        isTeamBusy = true
        teamActivityMessage = L10n.teamCreating
        defer { isTeamBusy = false; teamActivityMessage = nil }

        let leader = leaderAssistantID
        let uniqueMembers = memberAssistantIDs.filter { id in
            !id.isEmpty && id != leader
        }.reduce(into: [String]()) { acc, id in
            if !acc.contains(id) { acc.append(id) }
        }

        func input(_ assistantID: String?, role: String, fallback: String) -> CoworkTeamAssistantInput {
            let assistant = assistants.first { $0.id == assistantID }
            return CoworkTeamAssistantInput(
                name: assistant?.displayName ?? fallback,
                role: role,
                model: teamModel(for: assistantID),
                assistantID: assistantID
            )
        }

        var slots = [input(leader, role: "lead", fallback: L10n.teamLeader)]
        for (index, memberID) in uniqueMembers.enumerated() {
            slots.append(input(memberID, role: "member", fallback: "\(L10n.teamMember) \(index + 1)"))
        }

        do {
            let team = try await client.createTeam(
                CoworkCreateTeamRequest(name: name, assistants: slots, workspace: workspace)
            )
            await refreshTeams()
            teamActivityMessage = L10n.teamOpening
            await openTeam(team.id)
            return activeTeamID == team.id
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
            return false
        }
    }

    func deleteTeam(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteTeam(id: id)
            if activeTeamID == id { closeTeam() }
            await refreshTeams()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func renameTeam(_ id: String, name: String) async {
        guard let client else { return }
        do {
            try await client.renameTeam(id: id, name: name)
            await refreshTeams()
            if activeTeamID == id { activeTeam = try? await client.getTeam(id: id) }
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    @discardableResult
    func addTeamMember(assistantID: String) async -> Bool {
        guard let client, let teamID = activeTeamID else { return false }
        guard !activeTeamAssistantIDs().contains(assistantID) else { return false }
        let assistant = assistants.first { $0.id == assistantID }
        isTeamBusy = true
        teamActivityMessage = L10n.teamAddingMember
        defer { isTeamBusy = false; teamActivityMessage = nil }
        do {
            try await client.addTeamAssistant(
                teamID: teamID,
                assistant: CoworkTeamAssistantInput(
                    name: assistant?.displayName ?? L10n.teamMember,
                    role: "member",
                    model: teamModel(for: assistantID),
                    assistantID: assistantID
                )
            )
            try await client.ensureTeamSession(teamID: teamID)
            await reloadActiveTeam()
            return true
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
            return false
        }
    }

    func removeTeamMember(slotID: String) async {
        guard let client, let teamID = activeTeamID else { return }
        do {
            try await client.removeTeamAssistant(teamID: teamID, slotID: slotID)
            teamSlotMessages[slotID] = nil
            await reloadActiveTeam()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    /// Sends a task to the leader; the leader delegates across member slots.
    func sendTeamTask(_ content: String) async {
        guard let client, let teamID = activeTeamID else { return }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isTeamBusy = true
        teamActivityMessage = L10n.teamSendingTask
        defer { isTeamBusy = false; teamActivityMessage = nil }
        do {
            try await client.sendTeamMessage(teamID: teamID, content: text)
            await refreshTeamRunState()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func sendTeamSlotMessage(slotID: String, content: String) async {
        guard let client, let teamID = activeTeamID else { return }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await client.sendTeamAgentMessage(teamID: teamID, slotID: slotID, content: text)
            await refreshTeamRunState()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func refreshTeamRunState() async {
        guard let client, let teamID = activeTeamID else { return }
        teamRunState = try? await client.getTeamRunState(teamID: teamID)
    }

    func cancelActiveTeamRun() async {
        guard let client, let teamID = activeTeamID, let runID = teamRunState?.teamRunID else { return }
        do {
            try await client.cancelTeamRun(teamID: teamID, runID: runID)
            await refreshTeamRunState()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func pauseTeamSlot(_ slotID: String) async {
        guard let client, let teamID = activeTeamID, let runID = teamRunState?.teamRunID else { return }
        try? await client.pauseTeamAgent(teamID: teamID, runID: runID, slotID: slotID)
        await refreshTeamRunState()
    }

    func cancelTeamSlot(_ slotID: String) async {
        guard let client, let teamID = activeTeamID, let runID = teamRunState?.teamRunID else { return }
        try? await client.cancelTeamAgentTurn(teamID: teamID, runID: runID, slotID: slotID)
        await refreshTeamRunState()
    }

    /// Loads each slot's conversation feed so the multi-column view stays current.
    func refreshTeamSlotFeeds() async {
        guard let client, let team = activeTeam else { return }
        await withTaskGroup(of: (String, [CoworkMessage]).self) { group in
            for slot in team.assistants {
                guard let conversationID = slot.conversationID else { continue }
                group.addTask {
                    let page = try? await client.listMessages(conversationID: conversationID, limit: 40)
                    return (slot.slotID, page?.items ?? [])
                }
            }
            for await (slotID, items) in group {
                teamSlotMessages[slotID] = items
            }
        }
    }

    func reloadActiveTeam() async {
        guard let client, let teamID = activeTeamID else { return }
        do {
            activeTeam = try await client.getTeam(id: teamID)
            await refreshTeamSlotFeeds()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    /// Called from the WebSocket team.* events.
    func onTeamEvent() async {
        await reloadActiveTeam()
        await refreshTeamRunState()
        await refreshTeams()
    }

    /// Cloud/local model for Keep (`aionrs`); ACP CLI agents bring their own auth and model.
    private func teamModel(for assistantID: String?) -> String {
        guard let assistantID,
              let assistant = assistants.first(where: { $0.id == assistantID }) else {
            return selectedModelID ?? "default"
        }
        if assistant.isAionrs {
            return selectedModelID ?? "default"
        }
        return "default"
    }
}
