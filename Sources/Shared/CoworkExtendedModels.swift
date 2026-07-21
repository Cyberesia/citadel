import Foundation

// MARK: - Token usage

struct CoworkTokenUsage: Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }

    static func parse(from value: CoworkJSONValue?) -> CoworkTokenUsage? {
        guard let object = value?.objectValue else { return nil }
        let input = object.int(for: "input_tokens") ?? object.int(for: "prompt_tokens") ?? 0
        let output = object.int(for: "output_tokens") ?? object.int(for: "completion_tokens") ?? 0
        guard input > 0 || output > 0 else { return nil }
        return CoworkTokenUsage(inputTokens: input, outputTokens: output)
    }
}

/// Aggregated usage for the active conversation (Aisance conversation-usage-summary).
struct CoworkConversationUsageStats: Equatable, Sendable {
    var totalInputTokens = 0
    var totalOutputTokens = 0
    var turnCount = 0
    var modelCounts: [String: Int] = [:]
    var providerCounts: [String: Int] = [:]

    var totalTokens: Int { totalInputTokens + totalOutputTokens }

    var averageTokensPerTurn: Int {
        guard turnCount > 0 else { return 0 }
        return totalTokens / turnCount
    }

    mutating func record(usage: CoworkTokenUsage, model: String?, provider: String?) {
        totalInputTokens += usage.inputTokens
        totalOutputTokens += usage.outputTokens
        turnCount += 1
        if let model, !model.isEmpty {
            modelCounts[model, default: 0] += 1
        }
        if let provider, !provider.isEmpty {
            providerCounts[provider, default: 0] += 1
        }
    }
}

extension Dictionary where Key == String, Value == CoworkJSONValue {
    func int(for key: String) -> Int? {
        guard let value = self[key] else { return nil }
        if case .number(let n) = value { return Int(n) }
        if case .string(let s) = value { return Int(s) }
        return nil
    }
}

// MARK: - Conversation ops

struct CoworkCloneConversationRequest: Encodable {
    let conversation: CoworkConversationClonePayload
}

struct CoworkConversationClonePayload: Encodable {
    var id: String?
    var name: String?
    var type: String?
    var model: CoworkProviderModelRef?
    var extra: CoworkConversationExtra?
    var assistant: CoworkAssistantRef?
}

struct CoworkResetConversationRequest: Encodable {
    var keepWorkspace: Bool?

    enum CodingKeys: String, CodingKey {
        case keepWorkspace = "keep_workspace"
    }
}

// MARK: - Assistants CRUD
// Mirrors AionUI `assistantTypes.ts` / CoworkCore `AssistantDetail`.

struct CoworkAssistantProfile: Decodable, Hashable {
    let name: String
    let nameI18n: [String: String]?
    let description: String?
    let descriptionI18n: [String: String]?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case name, description, avatar
        case nameI18n = "name_i18n"
        case descriptionI18n = "description_i18n"
    }

    func localizedName(locale: String) -> String {
        CoworkAssistantLocalization.resolve(base: name, i18n: nameI18n, locale: locale)
    }

    func localizedDescription(locale: String) -> String {
        CoworkAssistantLocalization.resolve(base: description ?? "", i18n: descriptionI18n, locale: locale)
    }
}

struct CoworkAssistantLifecycle: Decodable, Hashable {
    let enabled: Bool
    let sortOrder: Int?
    let lastUsedAt: Double?

    enum CodingKeys: String, CodingKey {
        case enabled
        case sortOrder = "sort_order"
        case lastUsedAt = "last_used_at"
    }
}

struct CoworkAssistantEngine: Decodable, Hashable {
    let agentID: String?
    let agent: CoworkAssistantAgent?

    enum CodingKeys: String, CodingKey {
        case agent
        case agentID = "agent_id"
    }
}

struct CoworkAssistantRules: Decodable, Hashable {
    let content: String?
    let storageMode: String?

    enum CodingKeys: String, CodingKey {
        case content
        case storageMode = "storage_mode"
    }

    var resolvedContent: String { content ?? "" }
}

struct CoworkAssistantPrompts: Decodable, Hashable {
    let recommended: [String]?
    let recommendedI18n: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case recommended
        case recommendedI18n = "recommended_i18n"
    }

    func localizedRecommended(locale: String) -> [String] {
        let keys = CoworkAssistantLocalization.localeKeys(for: locale)
        for key in keys {
            if let prompts = recommendedI18n?[key], !prompts.isEmpty { return prompts }
        }
        return recommended ?? []
    }
}

struct CoworkAssistantDefaultScalar: Codable, Hashable {
    let mode: String
    let value: String?
}

struct CoworkAssistantDefaultList: Codable, Hashable {
    let mode: String
    let value: [String]?
}

struct CoworkAssistantDefaults: Decodable, Hashable {
    let model: CoworkAssistantDefaultScalar?
    let permission: CoworkAssistantDefaultScalar?
    let thoughtLevel: CoworkAssistantDefaultScalar?
    let skills: CoworkAssistantDefaultList?
    let mcps: CoworkAssistantDefaultList?

    enum CodingKeys: String, CodingKey {
        case model, permission, skills, mcps
        case thoughtLevel = "thought_level"
    }
}

struct CoworkAssistantCapabilities: Decodable, Hashable {
    let defaultSkillIDs: [String]?
    let customSkillNames: [String]?
    let defaultDisabledBuiltinSkillIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case customSkillNames = "custom_skill_names"
        case defaultSkillIDs = "default_skill_ids"
        case defaultDisabledBuiltinSkillIDs = "default_disabled_builtin_skill_ids"
    }
}

struct CoworkAssistantPreferences: Decodable, Hashable {
    let lastModelID: String?
    let lastPermissionValue: String?
    let lastThoughtLevelValue: String?
    let lastSkillIDs: [String]?
    let lastDisabledBuiltinSkillIDs: [String]?
    let lastMcpIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case lastModelID = "last_model_id"
        case lastPermissionValue = "last_permission_value"
        case lastThoughtLevelValue = "last_thought_level_value"
        case lastSkillIDs = "last_skill_ids"
        case lastDisabledBuiltinSkillIDs = "last_disabled_builtin_skill_ids"
        case lastMcpIDs = "last_mcp_ids"
    }
}

struct CoworkAssistantDetail: Identifiable, Decodable, Hashable {
    let id: String
    let source: String?
    let agentStatus: String?
    let agentStatusMessage: String?
    let teamSelectable: Bool?
    let teamBlockReason: String?
    let deletable: Bool?
    let profile: CoworkAssistantProfile
    let state: CoworkAssistantLifecycle
    let engine: CoworkAssistantEngine
    let rules: CoworkAssistantRules
    let prompts: CoworkAssistantPrompts
    let defaults: CoworkAssistantDefaults?
    let capabilities: CoworkAssistantCapabilities?
    let preferences: CoworkAssistantPreferences?

    enum CodingKeys: String, CodingKey {
        case id, source, profile, state, engine, rules, prompts, defaults, capabilities, preferences
        case agentStatus = "agent_status"
        case agentStatusMessage = "agent_status_message"
        case teamSelectable = "team_selectable"
        case teamBlockReason = "team_block_reason"
        case deletable
    }

    var isBuiltin: Bool { source == "builtin" }
    var isGenerated: Bool { source == "generated" }
    var isUserCreated: Bool { source == "user" || source == nil }
}

enum CoworkAssistantLocalization {
    static func localeKeys(for locale: String) -> [String] {
        var keys = [locale]
        if locale == "fr" { keys.append(contentsOf: ["fr-FR", "fr"]) }
        if locale == "en" { keys.append(contentsOf: ["en-US", "en"]) }
        if !keys.contains("en-US") { keys.append("en-US") }
        if !keys.contains("en") { keys.append("en") }
        return keys
    }

    static func resolve(base: String, i18n: [String: String]?, locale: String) -> String {
        for key in localeKeys(for: locale) {
            if let value = i18n?[key], !value.isEmpty { return value }
        }
        return base
    }
}

struct CoworkCreateAssistantRequest: Encodable {
    var id: String?
    var name: String
    var description: String?
    var avatar: String?
    var agentID: String?
    var recommendedPrompts: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, avatar
        case agentID = "agent_id"
        case recommendedPrompts = "recommended_prompts"
    }
}

struct CoworkUpdateAssistantRequest: Encodable {
    var name: String?
    var description: String?
    var avatar: String?
    var agentID: String?
    var recommendedPrompts: [String]?

    enum CodingKeys: String, CodingKey {
        case name, description, avatar
        case agentID = "agent_id"
        case recommendedPrompts = "recommended_prompts"
    }
}

struct CoworkSetAssistantStateRequest: Encodable {
    var enabled: Bool?
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case enabled
        case sortOrder = "sort_order"
    }
}

// MARK: - Skills hub

struct CoworkSkillRuleWriteRequest: Encodable {
    let assistantID: String
    let content: String
    var locale: String?

    enum CodingKeys: String, CodingKey {
        case content, locale
        case assistantID = "assistant_id"
    }
}

struct CoworkSkillRuleReadRequest: Encodable {
    let assistantID: String
    var locale: String?

    enum CodingKeys: String, CodingKey {
        case locale
        case assistantID = "assistant_id"
    }
}

// MARK: - Agents

struct CoworkManagedAgent: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let type: String?
    let enabled: Bool?
    let status: String?
    let description: String?
    let source: String?
    let health: String?
    let installed: Bool?
    let available: Bool?
    let command: String?
    let backend: String?
    let lastCheckStatus: String?
    let lastCheckErrorCode: String?
    let lastCheckErrorMessage: String?
    let lastCheckGuidance: String?

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, status, description, health, installed, available, command, backend
        case type = "agent_type"
        case source = "agent_source"
        case lastCheckStatus = "last_check_status"
        case lastCheckErrorCode = "last_check_error_code"
        case lastCheckErrorMessage = "last_check_error_message"
        case lastCheckGuidance = "last_check_guidance"
    }

    var displayName: String {
        name
            .replacingOccurrences(of: "AionUi", with: "Citadel Keep", options: .caseInsensitive)
            .replacingOccurrences(of: "Aion", with: "Keep", options: .caseInsensitive)
            .replacingOccurrences(of: "Cowork", with: "Keep", options: .caseInsensitive)
    }

    /// True when the backend resolved the agent CLI on $PATH.
    var isInstalled: Bool { installed ?? available ?? false }

    /// Management status from coworkcore: `online` | `offline` | `missing` | `unchecked`.
    var managementStatus: String {
        (status ?? "unchecked").lowercased()
    }

    var isHealthy: Bool { managementStatus == "online" || lastCheckStatus == "online" }

    /// Human-readable result of the last health probe (or install state).
    var healthSummary: String {
        if let msg = lastCheckErrorMessage, !msg.isEmpty { return msg }
        if let guidance = lastCheckGuidance, !guidance.isEmpty { return guidance }
        switch managementStatus {
        case "online": return L10n.agentHealthy
        case "offline": return L10n.agentUnhealthy
        case "missing": return L10n.agentMissingCLI
        default:
            return isInstalled ? L10n.agentUnchecked : L10n.notInstalledBadge
        }
    }

    var subtitleLine: String {
        let bits = [backend, type, source, command].compactMap { $0 }.filter { !$0.isEmpty }
        if bits.isEmpty { return "agent" }
        return bits.prefix(2).joined(separator: " · ")
    }
}

struct CoworkAgentTryConnectResult: Decodable {
    let success: Bool?
    let ok: Bool?
    let message: String?
    let error: String?

    var connected: Bool { success ?? ok ?? false }
    var detail: String? { message ?? error }
}

struct CoworkCustomAgentRequest: Encodable {
    let name: String
    let command: String
    var args: [String]?
    var env: [String: String]?
}

// MARK: - MCP OAuth

struct CoworkMcpOAuthStatusRequest: Encodable {
    let serverURL: String

    enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
    }
}

struct CoworkMcpOAuthStatusResponse: Decodable {
    let authenticated: Bool
}

struct CoworkMcpOAuthLoginResponse: Decodable {
    let success: Bool
    let error: String?
}

// MARK: - Snapshot

struct CoworkFSSnapshotPathRequest: Encodable {
    let workspace: String
    var filePath: String?

    enum CodingKeys: String, CodingKey {
        case workspace
        case filePath = "file_path"
    }
}

struct CoworkFSSnapshotDiscardRequest: Encodable {
    let workspace: String
    var filePaths: [String]?

    enum CodingKeys: String, CodingKey {
        case workspace
        case filePaths = "file_paths"
    }
}

// MARK: - Cron

struct CoworkCronJob: Identifiable, Decodable, Hashable {
    let id: String
    var name: String
    var enabled: Bool?
    var schedule: CoworkCronSchedule?
    var prompt: String?
    var assistantID: String?
    var conversationID: String?
    var lastRunAt: Double?
    var nextRunAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, schedule, prompt
        case assistantID = "assistant_id"
        case conversationID = "conversation_id"
        case lastRunAt = "last_run_at"
        case nextRunAt = "next_run_at"
    }
}

struct CoworkCronSchedule: Codable, Hashable {
    var kind: String?
    var expr: String?
    var tz: String?
    var description: String?
}

struct CoworkCreateCronJobRequest: Encodable {
    var name: String
    var enabled: Bool?
    var schedule: CoworkCronSchedule
    var prompt: String
    var assistantID: String?
    var conversationID: String?

    enum CodingKeys: String, CodingKey {
        case name, enabled, schedule, prompt
        case assistantID = "assistant_id"
        case conversationID = "conversation_id"
    }
}

struct CoworkUpdateCronJobRequest: Encodable {
    var name: String?
    var enabled: Bool?
    var schedule: CoworkCronSchedule?
    var prompt: String?
}

struct CoworkCronRunResult: Decodable {
    let conversationID: String?

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
    }
}

// MARK: - Client settings

struct CoworkClientSettingResponse<T: Decodable>: Decodable {
    let value: T?
}

struct CoworkClientSettingWriteRequest: Encodable {
    let value: CoworkJSONValue
}

// MARK: - STT

struct CoworkSTTResult: Decodable {
    let text: String?
}
