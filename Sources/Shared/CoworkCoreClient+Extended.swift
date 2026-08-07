import Foundation

extension CoworkCoreClient {
    // MARK: - Conversations

    func resetConversation(id: String, keepWorkspace: Bool = true) async throws {
        let _: CoworkEmpty = try await request(
            "POST",
            path: "api/conversations/\(id)/reset",
            body: CoworkResetConversationRequest(keepWorkspace: keepWorkspace)
        )
    }

    func cloneConversation(_ payload: CoworkConversationClonePayload) async throws -> CoworkConversation {
        try await request("POST", path: "api/conversations/clone", body: CoworkCloneConversationRequest(conversation: payload))
    }

    // MARK: - Assistants

    func getAssistant(id: String, locale: String? = nil) async throws -> CoworkAssistantDetail {
        var path = "api/assistants/\(id)"
        if let locale, let encoded = locale.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?locale=\(encoded)"
        }
        return try await request("GET", path: path)
    }

    func createAssistant(_ body: CoworkCreateAssistantRequest) async throws -> CoworkAssistant {
        try await request("POST", path: "api/assistants", body: body)
    }

    func updateAssistant(id: String, _ body: CoworkUpdateAssistantRequest) async throws -> CoworkAssistant {
        try await request("PUT", path: "api/assistants/\(id)", body: body)
    }

    func setAssistantState(id: String, enabled: Bool? = nil, sortOrder: Int? = nil) async throws -> CoworkAssistant {
        try await request(
            "PATCH",
            path: "api/assistants/\(id)/state",
            body: CoworkSetAssistantStateRequest(enabled: enabled, sortOrder: sortOrder)
        )
    }

    func deleteAssistant(id: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/assistants/\(id)")
    }

    // MARK: - Skills

    func readAssistantRule(assistantID: String, locale: String? = nil) async throws -> String {
        try await request(
            "POST",
            path: "api/skills/assistant-rule/read",
            body: CoworkSkillRuleReadRequest(assistantID: assistantID, locale: locale)
        )
    }

    func writeAssistantRule(assistantID: String, content: String, locale: String? = nil) async throws {
        let _: CoworkEmpty = try await request(
            "POST",
            path: "api/skills/assistant-rule/write",
            body: CoworkSkillRuleWriteRequest(assistantID: assistantID, content: content, locale: locale)
        )
    }

    func deleteAssistantRule(assistantID: String) async throws {
        let encoded = assistantID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? assistantID
        let _: CoworkEmpty = try await request("DELETE", path: "api/skills/assistant-rule/\(encoded)")
    }

    func readBuiltinSkill(fileName: String) async throws -> String {
        struct Body: Encodable { let fileName: String; enum CodingKeys: String, CodingKey { case fileName = "file_name" } }
        return try await request("POST", path: "api/skills/builtin-skill", body: Body(fileName: fileName))
    }

    // MARK: - Agents

    func listManagedAgents() async throws -> [CoworkManagedAgent] {
        try await request("GET", path: "api/agents/management")
    }

    /// Asks the backend to re-scan $PATH for installed CLI agents (claude, codex, gemini…).
    func refreshAgentCatalog() async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/agents/refresh", body: CoworkEmptyBody())
    }

    func tryConnectCustomAgent(_ body: CoworkCustomAgentRequest) async throws -> CoworkAgentTryConnectResult {
        try await request("POST", path: "api/agents/custom/try-connect", body: body)
    }

    /// Returns the updated management row (status / last_check_*). Not a `{healthy,message}` envelope.
    func agentHealthCheck(id: String) async throws -> CoworkManagedAgent {
        try await request("POST", path: "api/agents/\(id)/health-check", body: CoworkEmptyBody())
    }

    func setAgentEnabled(id: String, enabled: Bool) async throws {
        struct Body: Encodable { let enabled: Bool }
        let _: CoworkEmpty = try await request("PATCH", path: "api/agents/\(id)/enabled", body: Body(enabled: enabled))
    }

    func connectCustomAgent(_ body: CoworkCustomAgentRequest) async throws -> CoworkManagedAgent {
        try await request("POST", path: "api/agents/custom", body: body)
    }

    // MARK: - MCP OAuth

    func mcpOAuthStatus(serverURL: String) async throws -> CoworkMcpOAuthStatusResponse {
        try await request("POST", path: "api/mcp/oauth/check-status", body: CoworkMcpOAuthStatusRequest(serverURL: serverURL))
    }

    func mcpOAuthLogin(serverURL: String) async throws -> CoworkMcpOAuthLoginResponse {
        try await request("POST", path: "api/mcp/oauth/login", body: CoworkMcpOAuthStatusRequest(serverURL: serverURL))
    }

    func mcpOAuthLogout(serverURL: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/mcp/oauth/logout", body: CoworkMcpOAuthStatusRequest(serverURL: serverURL))
    }

    func mcpOAuthAuthenticatedServers() async throws -> [String] {
        try await request("GET", path: "api/mcp/oauth/authenticated")
    }

    // MARK: - Snapshot

    func stageSnapshotFile(workspace: String, filePath: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/fs/snapshot/stage", body: CoworkFSSnapshotPathRequest(workspace: workspace, filePath: filePath))
    }

    func stageAllSnapshot(workspace: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/fs/snapshot/stage-all", body: CoworkFSWorkspaceRequest(workspace: workspace))
    }

    func discardSnapshot(workspace: String, filePaths: [String]? = nil) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/fs/snapshot/discard", body: CoworkFSSnapshotDiscardRequest(workspace: workspace, filePaths: filePaths))
    }

    func resetSnapshot(workspace: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/fs/snapshot/reset", body: CoworkFSWorkspaceRequest(workspace: workspace))
    }

    func writeFile(path: String, data: String, workspace: String?) async throws {
        struct Body: Encodable { let path: String; let data: String; let workspace: String? }
        let _: CoworkEmpty = try await request("POST", path: "api/fs/write", body: Body(path: path, data: data, workspace: workspace))
    }

    func readFileBuffer(path: String, workspace: String?) async throws -> String? {
        try await request("POST", path: "api/fs/read-buffer", body: CoworkFSReadRequest(path: path, workspace: workspace))
    }

    /// Import macOS picker paths into the conversation workspace (AionUi `copyFilesToWorkspace`).
    func copyFilesToWorkspace(filePaths: [String], workspace: String) async throws -> CoworkFSCopyResult {
        try await request(
            "POST",
            path: "api/fs/copy",
            body: CoworkFSCopyRequest(filePaths: filePaths, workspace: workspace)
        )
    }

    // MARK: - Cron

    func listCronJobs(conversationID: String? = nil) async throws -> [CoworkCronJob] {
        var path = "api/cron/jobs"
        if let conversationID, let encoded = conversationID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?conversation_id=\(encoded)"
        }
        return try await request("GET", path: path)
    }

    func getCronJob(id: String) async throws -> CoworkCronJob? {
        try await request("GET", path: "api/cron/jobs/\(id)")
    }

    func createCronJob(_ body: CoworkCreateCronJobRequest) async throws -> CoworkCronJob {
        try await request("POST", path: "api/cron/jobs", body: body)
    }

    func updateCronJob(id: String, _ body: CoworkUpdateCronJobRequest) async throws -> CoworkCronJob {
        try await request("PUT", path: "api/cron/jobs/\(id)", body: body)
    }

    func deleteCronJob(id: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/cron/jobs/\(id)")
    }

    func runCronJobNow(id: String) async throws -> CoworkCronRunResult {
        try await request("POST", path: "api/cron/jobs/\(id)/run", body: CoworkEmptyBody())
    }

    // MARK: - STT

    func transcribeAudio(base64: String) async throws -> String {
        struct Body: Encodable { let audio: String }
        let result: CoworkSTTResult = try await request("POST", path: "api/stt", body: Body(audio: base64))
        return result.text ?? ""
    }

    // MARK: - Shell

    func openFileInEditor(path: String) async throws {
        struct Body: Encodable { let filePath: String; enum CodingKeys: String, CodingKey { case filePath = "file_path" } }
        let _: CoworkEmpty = try await request("POST", path: "api/shell/open-file", body: Body(filePath: path))
    }

    // MARK: - Private helpers

    private struct CoworkEmptyBody: Encodable {}
    private struct CoworkEmpty: Decodable {}
}
