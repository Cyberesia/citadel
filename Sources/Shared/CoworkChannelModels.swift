import Foundation

// MARK: - Chat platform bridges (plan Phase 6: /api/channel/*)

struct CoworkChannelPlugin: Identifiable, Decodable, Hashable {
    let pluginID: String?
    let rawID: String?
    let type: String?
    let name: String?
    let enabled: Bool?
    let connected: Bool?
    let status: String?
    let error: String?
    let activeUsers: Int?
    let botUsername: String?
    let hasToken: Bool?

    var id: String { pluginID ?? rawID ?? name ?? UUID().uuidString }
    var isEnabled: Bool { enabled ?? false }
    var isConnected: Bool { connected ?? false }

    enum CodingKeys: String, CodingKey {
        case pluginID = "plugin_id"
        case rawID = "id"
        case type, name, enabled, connected, status, error
        case activeUsers = "active_users"
        case botUsername = "bot_username"
        case hasToken = "has_token"
    }
}

struct CoworkChannelPairing: Identifiable, Decodable, Hashable {
    let code: String
    let platformUserID: String?
    let platformType: String?
    let displayName: String?
    let requestedAt: Double?
    let expiresAt: Double?

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code
        case platformUserID = "platform_user_id"
        case platformType = "platform_type"
        case displayName = "display_name"
        case requestedAt = "requested_at"
        case expiresAt = "expires_at"
    }
}

struct CoworkChannelUser: Identifiable, Decodable, Hashable {
    let id: String
    let platformUserID: String?
    let platformType: String?
    let displayName: String?
    let authorizedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case platformUserID = "platform_user_id"
        case platformType = "platform_type"
        case displayName = "display_name"
        case authorizedAt = "authorized_at"
    }
}

struct CoworkChannelTestResult: Decodable {
    let success: Bool?
    let botUsername: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, error
        case botUsername = "bot_username"
    }
}
