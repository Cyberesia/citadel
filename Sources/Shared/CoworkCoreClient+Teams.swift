import Foundation

// MARK: - Teams API (CoworkCore /api/teams/*)

extension CoworkCoreClient {
    private struct CoworkEmpty: Decodable {}
    private struct CoworkEmptyBody: Encodable {}

    func listTeams() async throws -> [CoworkTeam] {
        try await request("GET", path: "api/teams")
    }

    func getTeam(id: String) async throws -> CoworkTeam {
        try await request("GET", path: "api/teams/\(id)")
    }

    func createTeam(_ body: CoworkCreateTeamRequest) async throws -> CoworkTeam {
        try await request("POST", path: "api/teams", body: body)
    }

    func deleteTeam(id: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/teams/\(id)")
    }

    func renameTeam(id: String, name: String) async throws {
        struct Body: Encodable { let name: String }
        let _: CoworkEmpty = try await request("PATCH", path: "api/teams/\(id)/name", body: Body(name: name))
    }

    func addTeamAssistant(teamID: String, assistant: CoworkTeamAssistantInput) async throws {
        struct Body: Encodable { let assistant: CoworkTeamAssistantInput }
        let _: CoworkEmpty = try await request("POST", path: "api/teams/\(teamID)/agents", body: Body(assistant: assistant))
    }

    func removeTeamAssistant(teamID: String, slotID: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/teams/\(teamID)/agents/\(slotID)")
    }

    func renameTeamAssistant(teamID: String, slotID: String, name: String) async throws {
        struct Body: Encodable { let name: String }
        let _: CoworkEmpty = try await request("PATCH", path: "api/teams/\(teamID)/agents/\(slotID)/name", body: Body(name: name))
    }

    /// Spins up runtimes for the team's agents.
    func ensureTeamSession(teamID: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/teams/\(teamID)/session", body: CoworkEmptyBody())
    }

    func stopTeamSession(teamID: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/teams/\(teamID)/session")
    }

    func acquireTeamLease(teamID: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/teams/\(teamID)/active-lease", body: CoworkEmptyBody())
    }

    /// Dispatches a task to the team leader, which delegates to members.
    func sendTeamMessage(teamID: String, content: String, files: [String]? = nil) async throws {
        let _: CoworkEmpty = try await request(
            "POST",
            path: "api/teams/\(teamID)/messages",
            body: CoworkTeamMessageRequest(content: content, files: files)
        )
    }

    /// Direct message to a specific team member slot.
    func sendTeamAgentMessage(teamID: String, slotID: String, content: String) async throws {
        let _: CoworkEmpty = try await request(
            "POST",
            path: "api/teams/\(teamID)/agents/\(slotID)/messages",
            body: CoworkTeamMessageRequest(content: content, files: nil)
        )
    }

    func getTeamRunState(teamID: String) async throws -> CoworkTeamRunState {
        try await request("GET", path: "api/teams/\(teamID)/run-state")
    }

    func cancelTeamRun(teamID: String, runID: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/teams/\(teamID)/runs/\(runID)/cancel", body: CoworkEmptyBody())
    }

    func cancelTeamAgentTurn(teamID: String, runID: String, slotID: String) async throws {
        let _: CoworkEmpty = try await request(
            "POST",
            path: "api/teams/\(teamID)/runs/\(runID)/agents/\(slotID)/cancel",
            body: CoworkEmptyBody()
        )
    }

    func pauseTeamAgent(teamID: String, runID: String, slotID: String) async throws {
        let _: CoworkEmpty = try await request(
            "POST",
            path: "api/teams/\(teamID)/runs/\(runID)/agents/\(slotID)/pause",
            body: CoworkEmptyBody()
        )
    }
}
