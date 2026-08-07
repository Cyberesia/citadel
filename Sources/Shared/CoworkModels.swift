import Foundation

// MARK: - API envelope

struct CoworkAPIEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let error: String?
}

// MARK: - Assistants

struct CoworkAssistant: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let avatar: String?
    let enabled: Bool?
    let agent: CoworkAssistantAgent?
    let agentStatus: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, name, avatar, enabled, agent, source
        case agentStatus = "agent_status"
    }

    var isBuiltin: Bool { source == "builtin" }
    var isGenerated: Bool { source == "generated" }
    var isUserCreated: Bool { source == "user" || source == nil }

    var backendType: String { agent?.type ?? "aionrs" }
    var isAionrs: Bool { backendType == "aionrs" }

    /// User-visible label — upstream Aion/AionUi names are never shown in Citadel UI.
    var displayName: String {
        if let mapped = Self.knownDisplayNames[id] {
            return mapped
        }
        return CoworkUserFacing.assistantDisplayName(id: id, rawName: name)
    }

    /// Short backend badge for the assistants grid.
    var displayBackendType: String {
        switch backendType {
        case "aionrs": return "Keep"
        case "acp": return "ACP"
        default: return backendType.uppercased()
        }
    }

    private static let knownDisplayNames: [String: String] = [
        "aionui-assistant": "Citadel Keep",
        "cowork": "Keep",
        "bare:632f31d2": "Keep CLI",
    ]
}

struct CoworkAssistantAgent: Codable, Hashable {
    let type: String?
    let source: String?
}

// MARK: - Providers / models

struct CoworkProvider: Identifiable, Codable, Hashable {
    var id: String
    var platform: String
    var name: String
    var baseURL: String
    var apiKey: String
    var models: [String]
    var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, platform, name, models, enabled
        case baseURL = "base_url"
        case apiKey = "api_key"
    }

    var displayModel: String { models.first ?? "—" }
}

struct CoworkProviderModelRef: Codable, Hashable {
    let providerID: String
    let model: String

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case model
    }
}

struct CoworkFetchModelsResponse: Decodable {
    let models: [CoworkModelOption]
    let fixedBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case models
        case fixedBaseURL = "fixed_base_url"
    }
}

enum CoworkModelOption: Decodable, Hashable, Identifiable {
    case id(String)
    case named(id: String, name: String)

    var id: String {
        switch self {
        case .id(let value): return value
        case .named(let id, _): return id
        }
    }

    var label: String {
        switch self {
        case .id(let value): return value
        case .named(_, let name): return name
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .id(string)
            return
        }
        struct Named: Decodable { let id: String; let name: String }
        let named = try container.decode(Named.self)
        self = .named(id: named.id, name: named.name)
    }
}

struct CoworkCreateProviderRequest: Encodable {
    var id: String?
    var platform: String
    var name: String
    var baseURL: String
    var apiKey: String
    var models: [String]?
    var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, platform, name, models, enabled
        case baseURL = "base_url"
        case apiKey = "api_key"
    }
}

struct CoworkUpdateProviderRequest: Encodable {
    var name: String?
    var baseURL: String?
    var apiKey: String?
    var models: [String]?
    var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name, models, enabled
        case baseURL = "base_url"
        case apiKey = "api_key"
    }
}

struct CoworkFetchModelsRequest: Encodable {
    var platform: String
    var baseURL: String?
    var apiKey: String
    var tryFix: Bool?

    enum CodingKeys: String, CodingKey {
        case platform, apiKey = "api_key"
        case baseURL = "base_url"
        case tryFix = "try_fix"
    }
}

// MARK: - Conversations

struct CoworkConversation: Identifiable, Decodable, Hashable {
    let id: String
    var name: String?
    let type: String?
    let createdAt: Double?
    let updatedAt: Double?
    let model: CoworkProviderModelRef?
    let extra: CoworkConversationExtra?

    var workspacePath: String? { extra?.workspace }

    enum CodingKeys: String, CodingKey {
        case id, name, type, model, extra
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CoworkConversationPage: Decodable {
    let items: [CoworkConversation]
    let total: Int?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case items, total
        case hasMore = "has_more"
    }
}

struct CoworkCreateConversationRequest: Encodable {
    var name: String?
    var model: CoworkProviderModelRef?
    var assistant: CoworkAssistantRef?
    var extra: CoworkConversationExtra?
}

struct CoworkAssistantRef: Encodable {
    let id: String
    var locale: String?
    var conversationOverrides: CoworkConversationOverrides?

    enum CodingKeys: String, CodingKey {
        case id, locale
        case conversationOverrides = "conversation_overrides"
    }
}

struct CoworkConversationOverrides: Encodable {
    var model: String?
    var permission: String?
    var mcpIDs: [String]?
    var skillIDs: [String]?
    var disabledBuiltinSkillIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case model, permission
        case mcpIDs = "mcp_ids"
        case skillIDs = "skill_ids"
        case disabledBuiltinSkillIDs = "disabled_builtin_skill_ids"
    }
}

// MARK: - Chat file refs (aligned with AionCore ChatFileRef)

/// Source-tagged file reference sent with messages — backend resolves `local` paths on this Mac.
struct CoworkChatFileRef: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case local
        case upload
        case project
    }

    let kind: Kind
    var path: String?
    var peID: String?
    var relativePath: String?

    enum CodingKeys: String, CodingKey {
        case kind, path
        case peID = "pe_id"
        case relativePath = "relative_path"
    }

    static func local(_ path: String) -> CoworkChatFileRef {
        CoworkChatFileRef(kind: .local, path: path, peID: nil, relativePath: nil)
    }

    static func localRefs(from paths: [String]) -> [CoworkChatFileRef] {
        paths.map { .local($0) }
    }

    init(kind: Kind, path: String?, peID: String?, relativePath: String?) {
        self.kind = kind
        self.path = path
        self.peID = peID
        self.relativePath = relativePath
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let kind = try? container.decode(Kind.self, forKey: .kind) {
            self.kind = kind
            path = try container.decodeIfPresent(String.self, forKey: .path)
            peID = try container.decodeIfPresent(String.self, forKey: .peID)
            relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
            return
        }
        let legacyPath = try decoder.singleValueContainer().decode(String.self)
        self = .local(legacyPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch kind {
        case .local, .upload:
            try container.encode(path, forKey: .path)
        case .project:
            try container.encode(peID, forKey: .peID)
            try container.encode(relativePath, forKey: .relativePath)
        }
    }
}

struct CoworkConversationExtra: Codable, Hashable {
    var workspace: String?
    var customWorkspace: Bool?
    var defaultFiles: [String]?
    var selectedMcpServerIDs: [String]?
    var selectedSessionMcpServers: [CoworkSessionMcpServer]?
    var permission: String?
    var skillIDs: [String]?
    var lastTokenUsage: Int?
    /// Create-time: agent rules for chat-only models.
    var presetContext: String?
    var enabledSkills: [String]?
    var excludeBuiltinSkills: [String]?
    var excludeAutoInjectSkills: [String]?

    enum CodingKeys: String, CodingKey {
        case workspace
        case customWorkspace = "custom_workspace"
        case defaultFiles = "default_files"
        case selectedMcpServerIDs = "selected_mcp_server_ids"
        case selectedSessionMcpServers = "selected_session_mcp_servers"
        case permission
        case skillIDs = "skill_ids"
        case lastTokenUsage = "last_token_usage"
        case presetContext = "preset_context"
        case enabledSkills = "enabled_skills"
        case excludeBuiltinSkills = "exclude_builtin_skills"
        case excludeAutoInjectSkills = "exclude_auto_inject_skills"
    }
}

struct CoworkSessionMcpServer: Codable, Hashable {
    let id: String
    let name: String
    var transport: CoworkMcpTransport?
}

struct CoworkSendMessageRequest: Encodable {
    let input: String
    let conversationID: String
    var files: [CoworkChatFileRef]?

    enum CodingKeys: String, CodingKey {
        case input, files
        case conversationID = "conversation_id"
    }
}

struct CoworkSendMessageResult: Decodable {
    let msgID: String
    let turnID: String

    enum CodingKeys: String, CodingKey {
        case msgID = "msg_id"
        case turnID = "turn_id"
    }
}

// MARK: - Messages

struct CoworkMessage: Identifiable, Decodable, Hashable {
    let id: String?
    let msgID: String?
    let type: String?
    let position: String?
    let conversationID: String?
    let createdAt: Double?
    let status: String?
    let hidden: Bool?
    let content: CoworkMessageContent?

    var stableID: String { msgID ?? id ?? UUID().uuidString }
    var isUser: Bool { position == "right" }
    var isTips: Bool { type == "tips" }
    var isThinking: Bool { type == "thinking" }
    var isToolMessage: Bool { type == "tool_call" || type == "tool_group" || type == "acp_tool_call" }
    var textBody: String { content?.textBody ?? "" }
    var errorMessage: String? { content?.errorMessage }

    enum CodingKeys: String, CodingKey {
        case id, type, position, content, status, hidden
        case msgID = "msg_id"
        case conversationID = "conversation_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        msgID = try c.decodeIfPresent(String.self, forKey: .msgID)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        position = try c.decodeIfPresent(String.self, forKey: .position)
        conversationID = try c.decodeIfPresent(String.self, forKey: .conversationID)
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
        if let json = try? c.decode(CoworkJSONValue.self, forKey: .content) {
            content = CoworkMessageContent(json: json)
        } else {
            content = try c.decodeIfPresent(CoworkMessageContent.self, forKey: .content)
        }
    }
}

struct CoworkMessageContent: Decodable, Hashable {
    let content: String?
    let text: String?
    let type: String?
    let name: String?
    let status: String?
    let description: String?
    let callID: String?
    let json: CoworkJSONValue?

    var toolName: String? { name ?? json?.objectValue?["name"]?.stringValue }
    var argsJSON: CoworkJSONValue? { json?.objectValue?["args"] ?? json?.objectValue?["input"] }
    var inputJSON: CoworkJSONValue? { json?.objectValue?["input"] }
    var resultJSON: CoworkJSONValue? { json?.objectValue?["result"] ?? json?.objectValue?["output"] }
    var textBody: String {
        if let text, !text.isEmpty { return text }
        if let content, !content.isEmpty { return content }
        return ""
    }
    var errorMessage: String? {
        if let err = json?.objectValue?["error"]?.objectValue?["message"]?.stringValue { return err }
        if type == "error", let content, !content.isEmpty { return content }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case content, text, type, name, status, description
        case callID = "call_id"
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), !single.decodeNil() {
            if let string = try? single.decode(String.self) {
                content = string
                text = string
                type = nil; name = nil; status = nil; description = nil; callID = nil
                json = .string(string)
                return
            }
            if let value = try? single.decode(CoworkJSONValue.self) {
                json = value
                content = value.stringValue
                text = value.stringValue
                if let obj = value.objectValue {
                    type = obj["type"]?.stringValue
                    name = obj["name"]?.stringValue
                    status = obj["status"]?.stringValue
                    description = obj["description"]?.stringValue
                    callID = obj["call_id"]?.stringValue
                } else {
                    type = nil; name = nil; status = nil; description = nil; callID = nil
                }
                return
            }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        callID = try c.decodeIfPresent(String.self, forKey: .callID)
        json = nil
    }

    init(json: CoworkJSONValue) {
        self.json = json
        if let obj = json.objectValue {
            content = obj["content"]?.stringValue
            text = obj["text"]?.stringValue ?? content
            type = obj["type"]?.stringValue
            name = obj["name"]?.stringValue
            status = obj["status"]?.stringValue
            description = obj["description"]?.stringValue
            callID = obj["call_id"]?.stringValue
        } else {
            content = json.stringValue
            text = json.stringValue
            type = nil; name = nil; status = nil; description = nil; callID = nil
        }
    }
}

struct CoworkMessagePage: Decodable {
    let items: [CoworkMessage]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
    }
}

// MARK: - Skills / slash / file ops

struct CoworkUpdateConversationRequest: Encodable {
    var name: String?
    var model: CoworkProviderModelRef?
    var assistant: CoworkAssistantRef?
    var extra: CoworkConversationExtra?
    var mergeExtra: Bool?

    enum CodingKeys: String, CodingKey {
        case name, model, assistant, extra
        case mergeExtra = "merge_extra"
    }
}

struct CoworkSkill: Identifiable, Decodable, Hashable {
    let name: String
    let description: String?
    let path: String?

    var id: String { name }
}

struct CoworkSlashCommand: Identifiable, Decodable, Hashable {
    let name: String
    let description: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, description
    }
}

struct CoworkFileChange: Identifiable, Decodable, Hashable {
    let filePath: String
    let relativePath: String
    let operation: String

    var id: String { filePath }
    var displayPath: String { relativePath.isEmpty ? filePath : relativePath }

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case relativePath = "relative_path"
        case operation
        case path
        case status
    }

    init(filePath: String, relativePath: String, operation: String) {
        self.filePath = filePath
        self.relativePath = relativePath
        self.operation = operation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let fp = try c.decodeIfPresent(String.self, forKey: .filePath) {
            filePath = fp
            relativePath = try c.decodeIfPresent(String.self, forKey: .relativePath) ?? fp
            operation = try c.decodeIfPresent(String.self, forKey: .operation)
                ?? c.decodeIfPresent(String.self, forKey: .status) ?? "modify"
        } else {
            let legacyPath = try c.decode(String.self, forKey: .path)
            filePath = legacyPath
            relativePath = legacyPath
            operation = try c.decodeIfPresent(String.self, forKey: .status) ?? "modify"
        }
    }
}

struct CoworkFileSnapshotCompareResult: Decodable {
    let staged: [CoworkFileChange]?
    let unstaged: [CoworkFileChange]?

    var allChanges: [CoworkFileChange] {
        (staged ?? []) + (unstaged ?? [])
    }
}

struct CoworkFSRenameRequest: Encodable {
    let path: String
    let newName: String
    let workspace: String?

    enum CodingKeys: String, CodingKey {
        case path, workspace
        case newName = "new_name"
    }
}

struct CoworkFSPathRequest: Encodable {
    let path: String
    let workspace: String?
}

struct CoworkFSWorkspaceRequest: Encodable {
    let workspace: String
}

// MARK: - WebSocket

struct CoworkWSEvent: Decodable {
    let name: String?
    let event: String?
    let data: CoworkWSResponseMessage?
    let payload: CoworkWSResponseMessage?

    var eventName: String? { name ?? event }
    var body: CoworkWSResponseMessage? { data ?? payload }
}

/// CoworkCore `message.stream` WebSocket payload.
struct CoworkWSResponseMessage: Decodable {
    let type: String?
    let msgID: String?
    let turnID: String?
    let conversationID: String?
    let data: CoworkJSONValue?
    let replace: Bool?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case type, data, replace, status
        case msgID = "msg_id"
        case turnID = "turn_id"
        case conversationID = "conversation_id"
    }

    var textChunk: String? {
        guard let data else { return nil }
        if let string = data.stringValue, !string.isEmpty { return string }
        if let content = data.objectValue?["content"]?.stringValue, !content.isEmpty { return content }
        if let text = data.objectValue?["text"]?.stringValue, !text.isEmpty { return text }
        return nil
    }
}

// MARK: - Presets

enum CoworkLocalLLMBackend: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case mlx

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ollama: return "Ollama"
        case .mlx: return "Native MLX"
        }
    }
}

/// Home model picker tabs: local runtimes + BYOK cloud providers.
enum CoworkModelPickerTab: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case mlx
    case cloud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ollama: return "Ollama"
        case .mlx: return "Native MLX"
        case .cloud: return L10n.cloudTab
        }
    }

    var iconName: String {
        switch self {
        case .ollama: return "server.rack"
        case .mlx: return "cpu"
        case .cloud: return "cloud.fill"
        }
    }
}

enum CoworkProviderPreset: String, CaseIterable, Identifiable {
    case ollama
    case lmStudio
    case openAI
    case anthropic
    case gemini
    case xai
    case infomaniak
    case openRouter
    case custom

    var id: String { rawValue }

    /// Cloud BYOK providers that require an API key and support live model discovery.
    static var cloudCases: [CoworkProviderPreset] {
        [.openAI, .anthropic, .gemini, .xai, .infomaniak, .openRouter, .custom]
    }

    var isCloud: Bool {
        switch self {
        case .ollama, .lmStudio: return false
        default: return true
        }
    }

    var label: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .lmStudio: return "LM Studio (local)"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .xai: return "xAI (Grok)"
        case .infomaniak: return "Infomaniak kAI"
        case .openRouter: return "OpenRouter"
        case .custom: return "Custom endpoint"
        }
    }

    var platform: String {
        switch self {
        case .ollama, .lmStudio, .custom: return "custom"
        case .openAI: return "openai"
        case .anthropic: return "anthropic"
        case .gemini: return "gemini"
        case .xai: return "xai"
        case .infomaniak: return "infomaniak"
        case .openRouter: return "openrouter"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434"
        case .lmStudio: return "http://127.0.0.1:1234"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .xai: return "https://api.x.ai/v1"
        case .infomaniak: return "https://api.infomaniak.com"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        }
    }

    var defaultAPIKeyPlaceholder: String {
        switch self {
        case .ollama: return "ollama"
        case .lmStudio: return "lm-studio"
        default: return ""
        }
    }

    static func from(platform: String) -> CoworkProviderPreset {
        switch platform.lowercased() {
        case "openai": return .openAI
        case "anthropic": return .anthropic
        case "gemini", "google": return .gemini
        case "xai": return .xai
        case "infomaniak": return .infomaniak
        case "openrouter": return .openRouter
        default: return .custom
        }
    }

    var iconName: String {
        switch self {
        case .openAI: return "sparkles"
        case .anthropic: return "brain.head.profile"
        case .gemini: return "globe.americas.fill"
        case .xai: return "bolt.fill"
        case .infomaniak: return "cloud.fill"
        case .openRouter: return "arrow.triangle.branch"
        case .ollama: return "server.rack"
        case .lmStudio: return "desktopcomputer"
        case .custom: return "link"
        }
    }
}

// MARK: - Workspace / filesystem

struct CoworkFSEntry: Identifiable, Decodable, Hashable {
    let name: String
    let type: String

    var id: String { name }
    var isDirectory: Bool { type == "directory" }

    var iconName: String {
        isDirectory ? "folder.fill" : "doc.fill"
    }
}

struct CoworkFSReadRequest: Encodable {
    let path: String
    let workspace: String?

    enum CodingKeys: String, CodingKey {
        case path, workspace
    }
}

// MARK: - MCP

struct CoworkMcpServer: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let description: String?
    let enabled: Bool
    let builtin: Bool?
    let tools: [CoworkMcpTool]?
    let lastTestStatus: String?
    let transport: CoworkMcpTransport?

    enum CodingKeys: String, CodingKey {
        case id, name, description, enabled, builtin, tools, transport
        case lastTestStatus = "last_test_status"
    }

    /// URL for HTTP/SSE transports — the OAuth flows key off this.
    var httpURL: String? {
        guard let transport, transport.type != "stdio" else { return nil }
        return transport.url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        builtin = try container.decodeIfPresent(Bool.self, forKey: .builtin)
        tools = try container.decodeIfPresent([CoworkMcpTool].self, forKey: .tools)
        lastTestStatus = try container.decodeIfPresent(String.self, forKey: .lastTestStatus)
        transport = try container.decodeIfPresent(CoworkMcpTransport.self, forKey: .transport)
    }
}

struct CoworkMcpTool: Decodable, Hashable, Identifiable {
    let name: String
    let description: String?
    let inputSchema: CoworkJSONValue?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct CoworkMcpImportRequest: Encodable {
    let servers: [CoworkMcpImportServer]
}

struct CoworkMcpTestConnectionRequest: Encodable {
    var id: String?
    let name: String
    let transport: CoworkMcpTransport

    enum CodingKeys: String, CodingKey {
        case id, name, transport
    }
}

struct CoworkMcpConnectionTestResult: Decodable {
    let success: Bool
    let tools: [CoworkMcpTool]?
    let error: String?
    let code: String?
    let needsAuth: Bool?

    enum CodingKeys: String, CodingKey {
        case success, tools, error, code
        case needsAuth = "needs_auth"
    }
}

struct CoworkMcpImportServer: Encodable {
    let name: String
    let description: String?
    let transport: CoworkMcpTransport
    let originalJSON: String
    let builtin: Bool?

    enum CodingKeys: String, CodingKey {
        case name, description, transport, builtin
        case originalJSON = "original_json"
    }
}

struct CoworkMcpTransport: Codable, Hashable {
    let type: String
    let command: String?
    let args: [String]?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case type, command, args, url
    }
}

struct CoworkMcpAgentConfigGroup: Decodable, Hashable {
    let source: String
    let servers: [CoworkMcpDetectedServer]
}

struct CoworkMcpDetectedServer: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let description: String?
    let enabled: Bool?
    let importable: Bool?
    let importSkipReason: String?
    let builtin: Bool?
    let transport: CoworkMcpDetectedTransport?

    enum CodingKeys: String, CodingKey {
        case id, name, description, enabled, importable, builtin, transport
        case importSkipReason = "import_skip_reason"
    }

    var canImport: Bool { importable == true }
}

struct CoworkMcpDetectedTransport: Decodable, Hashable {
    let type: String
    let command: String?
    let args: [String]?
    let url: String?
}

// MARK: - Confirmations

struct CoworkConfirmation: Identifiable, Decodable, Hashable {
    let id: String
    let title: String?
    let description: String
    let callID: String
    let conversationID: String?
    let msgID: String?
    let options: [CoworkConfirmationOption]

    enum CodingKeys: String, CodingKey {
        case id, title, description, options
        case callID = "call_id"
        case conversationID = "conversation_id"
        case msgID = "msg_id"
    }
}

struct CoworkConfirmationOption: Decodable, Hashable, Identifiable {
    let label: String
    let value: String

    var id: String { value }
}

struct CoworkConfirmRequest: Encodable {
    let confirmKey: String
    let msgID: String
    let conversationID: String
    let callID: String

    enum CodingKeys: String, CodingKey {
        case msgID = "msg_id"
        case conversationID = "conversation_id"
        case callID = "call_id"
        case confirmKey = "confirm_key"
    }
}

// MARK: - Preview

struct CoworkPreviewItem: Identifiable, Hashable {
    let id: String
    var title: String
    var path: String?
    var content: String
    var contentType: CoworkPreviewContentType
    var imageBase64: String?
    var diffOldText: String?
}

enum CoworkPreviewContentType: String, Hashable {
    case text
    case markdown
    case code
    case image
    case html
    case pdf
    case diff
    case binary
}

struct CoworkPreviewOpenEvent: Decodable {
    let content: String?
    let contentType: String?
    let metadata: CoworkPreviewMetadata?

    enum CodingKeys: String, CodingKey {
        case content
        case contentType = "content_type"
        case metadata
    }
}

struct CoworkPreviewMetadata: Decodable {
    let title: String?
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case title
        case fileName = "file_name"
    }
}
