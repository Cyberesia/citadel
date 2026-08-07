import Foundation

/// HTTP bridge to CoworkCore with `{ success, data }` envelope unwrapping.
struct CoworkCoreClient: Sendable {
    let port: Int
    private let session: URLSession

    init(port: Int, session: URLSession = .shared) {
        self.port = port
        self.session = session
    }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }
    var webSocketURL: URL { URL(string: "ws://127.0.0.1:\(port)/ws")! }

    func isHealthy() async -> Bool {
        do {
            let _: CoworkHealth = try await request("GET", path: "health")
            return true
        } catch {
            return false
        }
    }

    func listAssistants() async throws -> [CoworkAssistant] {
        try await request("GET", path: "api/assistants")
    }

    func listProviders() async throws -> [CoworkProvider] {
        try await request("GET", path: "api/providers")
    }

    func createProvider(_ body: CoworkCreateProviderRequest) async throws -> CoworkProvider {
        try await request("POST", path: "api/providers", body: body)
    }

    func updateProvider(id: String, _ body: CoworkUpdateProviderRequest) async throws -> CoworkProvider {
        try await request("PUT", path: "api/providers/\(id)", body: body)
    }

    func deleteProvider(id: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/providers/\(id)")
    }

    func fetchModels(_ body: CoworkFetchModelsRequest) async throws -> CoworkFetchModelsResponse {
        try await request("POST", path: "api/providers/fetch-models", body: body)
    }

    func listConversations(limit: Int = 50) async throws -> CoworkConversationPage {
        try await request("GET", path: "api/conversations?limit=\(limit)")
    }

    func getConversation(id: String) async throws -> CoworkConversation {
        try await request("GET", path: "api/conversations/\(id)")
    }

    func createConversation(_ body: CoworkCreateConversationRequest) async throws -> CoworkConversation {
        try await request("POST", path: "api/conversations", body: body)
    }

    func deleteConversation(id: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/conversations/\(id)")
    }

    func listMessages(conversationID: String, limit: Int = 100, before: String? = nil) async throws -> CoworkMessagePage {
        var path = "api/conversations/\(conversationID)/messages?limit=\(limit)"
        if let before, let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
        }
        return try await request("GET", path: path)
    }

    func updateConversation(id: String, name: String) async throws -> CoworkConversation {
        try await updateConversation(id: id, CoworkUpdateConversationRequest(name: name))
    }

    /// PATCH returns a bare success flag upstream, so re-fetch the updated conversation.
    @discardableResult
    func updateConversation(id: String, _ body: CoworkUpdateConversationRequest) async throws -> CoworkConversation {
        let _: CoworkEmpty = try await request("PATCH", path: "api/conversations/\(id)", body: body)
        return try await getConversation(id: id)
    }

    func listSkills() async throws -> [CoworkSkill] {
        try await request("GET", path: "api/skills")
    }

    func listSlashCommands(conversationID: String) async throws -> [CoworkSlashCommand] {
        try await request("GET", path: "api/conversations/\(conversationID)/slash-commands")
    }

    func ensureRuntime(conversationID: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/conversations/\(conversationID)/runtime/ensure", body: CoworkEmptyBody())
    }

    func searchMessages(conversationID: String, query: String) async throws -> [CoworkMessage] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await request("GET", path: "api/conversations/\(conversationID)/messages/search?q=\(encoded)")
    }

    func listWorkspace(conversationID: String, path: String = ".", search: String? = nil) async throws -> [CoworkFSEntry] {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        var urlPath = "api/conversations/\(conversationID)/workspace?path=\(encoded)"
        if let search, let s = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlPath += "&search=\(s)"
        }
        return try await request("GET", path: urlPath)
    }

    func renameWorkspaceEntry(path: String, newName: String, workspace: String?) async throws -> String {
        try await request("POST", path: "api/fs/rename", body: CoworkFSRenameRequest(path: path, newName: newName, workspace: workspace))
    }

    func removeWorkspaceEntry(path: String, workspace: String?) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/fs/remove", body: CoworkFSPathRequest(path: path, workspace: workspace))
    }

    func compareFileSnapshot(workspace: String) async throws -> CoworkFileSnapshotCompareResult {
        try await request("POST", path: "api/fs/snapshot/compare", body: CoworkFSWorkspaceRequest(workspace: workspace))
    }

    func snapshotBaseline(workspace: String, filePath: String) async throws -> String? {
        struct Body: Encodable {
            let workspace: String
            let filePath: String
            enum CodingKeys: String, CodingKey {
                case workspace
                case filePath = "file_path"
            }
        }
        return try await request("POST", path: "api/fs/snapshot/baseline", body: Body(workspace: workspace, filePath: filePath))
    }

    func initFileSnapshot(workspace: String) async throws {
        let _: CoworkEmpty = try await request("POST", path: "api/fs/snapshot/init", body: CoworkFSWorkspaceRequest(workspace: workspace))
    }

    func sendMessage(conversationID: String, input: String, files: [String] = []) async throws -> CoworkSendMessageResult {
        let body = CoworkSendMessageBody(content: input, files: files.isEmpty ? nil : files)
        return try await request("POST", path: "api/conversations/\(conversationID)/messages", body: body)
    }

    func cancelTurn(conversationID: String, turnID: String) async throws {
        let _: CoworkEmpty = try await request(
            "POST",
            path: "api/conversations/\(conversationID)/cancel",
            body: CoworkCancelTurnBody(turnID: turnID)
        )
    }

    func readFile(path: String, workspace: String?) async throws -> String? {
        try await request("POST", path: "api/fs/read", body: CoworkFSReadRequest(path: path, workspace: workspace))
    }

    func readImageBase64(path: String, workspace: String?) async throws -> String? {
        try await request("POST", path: "api/fs/image-base64", body: CoworkFSReadRequest(path: path, workspace: workspace))
    }

    func listMcpServers() async throws -> [CoworkMcpServer] {
        try await request("GET", path: "api/mcp/servers")
    }

    func listMcpAgentConfigs() async throws -> [CoworkMcpAgentConfigGroup] {
        try await request("GET", path: "api/mcp/agent-configs")
    }

    func toggleMcpServer(id: String) async throws -> CoworkMcpServer {
        try await request("POST", path: "api/mcp/servers/\(id)/toggle", body: CoworkEmptyBody())
    }

    func deleteMcpServer(id: String) async throws {
        let _: CoworkEmpty = try await request("DELETE", path: "api/mcp/servers/\(id)")
    }

    func importMcpServers(_ body: CoworkMcpImportRequest) async throws -> [CoworkMcpServer] {
        try await request("POST", path: "api/mcp/servers/import", body: body)
    }

    func listConfirmations(conversationID: String) async throws -> [CoworkConfirmation] {
        try await request("GET", path: "api/conversations/\(conversationID)/confirmations")
    }

    func confirmAction(conversationID: String, callID: String, msgID: String, confirmKey: String, alwaysAllow: Bool = false) async throws {
        let encodedCallID = callID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? callID
        let path = "api/conversations/\(conversationID)/confirmations/\(encodedCallID)/confirm"
        let _: CoworkEmpty = try await request(
            "POST",
            path: path,
            body: CoworkConfirmBody(msgID: msgID, data: confirmKey, alwaysAllow: alwaysAllow ? true : nil)
        )
    }

    // MARK: - Transport

    private struct CoworkHealth: Decodable { let status: String? }
    private struct CoworkEmpty: Decodable {}
    private struct CoworkEmptyBody: Encodable {}
    private struct CoworkCancelTurnBody: Encodable {
        let turnID: String

        enum CodingKeys: String, CodingKey {
            case turnID = "turn_id"
        }
    }
    private struct CoworkConfirmBody: Encodable {
        let msgID: String
        let data: String
        let alwaysAllow: Bool?

        enum CodingKeys: String, CodingKey {
            case msgID = "msg_id"
            case data
            case alwaysAllow = "always_allow"
        }
    }
    private struct CoworkSendMessageBody: Encodable {
        let content: String
        let files: [String]?
    }

    func request<T: Decodable>(_ method: String, path: String, body: (any Encodable)? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw CoworkCoreError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder.cowork.encode(AnyEncodable(body))
        }
        // Double-submit CSRF: echo the backend cookie so mutating calls pass in auth mode.
        if method != "GET",
           let cookies = HTTPCookieStorage.shared.cookies(for: baseURL),
           let csrf = cookies.first(where: { $0.name == "aionui-csrf-token" }) {
            req.setValue(csrf.value, forHTTPHeaderField: "x-csrf-token")
        }
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)

        if T.self == CoworkEmpty.self, data.isEmpty {
            return CoworkEmpty() as! T
        }

        if let envelope = try? JSONDecoder.cowork.decode(CoworkAPIEnvelope<T>.self, from: data),
           let payload = envelope.data {
            return payload
        }
        return try JSONDecoder.cowork.decode(T.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CoworkCoreError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CoworkCoreError.backendError(code: http.statusCode, message: message)
        }
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

extension JSONEncoder {
    static let cowork: JSONEncoder = {
        JSONEncoder()
    }()
}

extension JSONDecoder {
    static let cowork: JSONDecoder = {
        JSONDecoder()
    }()
}

public enum CoworkCoreError: LocalizedError, Sendable {
    case invalidResponse
    case backendError(code: Int, message: String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Keep returned an invalid response."
        case .backendError(let code, let message): return "Keep error (\(code)): \(message)"
        case .notConnected: return "Keep is not running."
        }
    }
}
