import Foundation

// MARK: - Teams orchestration (plan Phase 5)

extension CoworkState {
    func refreshTeams() async {
        guard let client else { return }
        do { teams = try await client.listTeams() }
        catch { teams = [] }
    }

    func openTeam(_ id: String) async {
        guard let client else { return }
        activeTeamID = id
        do {
            activeTeam = try await client.getTeam(id: id)
            try await client.ensureTeamSession(teamID: id)
            try? await client.acquireTeamLease(teamID: id)
            await refreshTeamRunState()
            await refreshTeamSlotFeeds()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    func closeTeam() {
        activeTeamID = nil
        activeTeam = nil
        teamRunState = nil
        teamSlotMessages = [:]
    }

    func createTeam(name: String, leaderAssistantID: String?, memberAssistantIDs: [String], workspace: String?) async {
        guard let client else { return }
        isTeamBusy = true
        defer { isTeamBusy = false }

        func input(_ assistantID: String?, role: String, fallback: String) -> CoworkTeamAssistantInput {
            let assistant = assistants.first { $0.id == assistantID }
            return CoworkTeamAssistantInput(
                name: assistant?.displayName ?? fallback,
                role: role,
                model: selectedModelID ?? "default",
                assistantID: assistantID
            )
        }

        var slots = [input(leaderAssistantID, role: "lead", fallback: L10n.teamLeader)]
        for (index, memberID) in memberAssistantIDs.enumerated() {
            slots.append(input(memberID, role: "member", fallback: "\(L10n.teamMember) \(index + 1)"))
        }

        do {
            let team = try await client.createTeam(
                CoworkCreateTeamRequest(name: name, assistants: slots, workspace: workspace)
            )
            await refreshTeams()
            await openTeam(team.id)
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
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

    func addTeamMember(assistantID: String) async {
        guard let client, let teamID = activeTeamID else { return }
        let assistant = assistants.first { $0.id == assistantID }
        do {
            try await client.addTeamAssistant(
                teamID: teamID,
                assistant: CoworkTeamAssistantInput(
                    name: assistant?.displayName ?? L10n.teamMember,
                    role: "member",
                    model: selectedModelID ?? "default",
                    assistantID: assistantID
                )
            )
            await reloadActiveTeam()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
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
        defer { isTeamBusy = false }
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
        activeTeam = try? await client.getTeam(id: teamID)
        await refreshTeamSlotFeeds()
    }

    /// Called from the WebSocket team.* events.
    func onTeamEvent() async {
        await reloadActiveTeam()
        await refreshTeamRunState()
        await refreshTeams()
    }
}
