import Foundation

// MARK: - Channel bridges API (/api/channel/*)

extension CoworkCoreClient {
    private struct CoworkEmpty: Decodable {}

    func listChannelPlugins() async throws -> [CoworkChannelPlugin] {
        try await request("GET", path: "api/channel/plugins")
    }

    func enableChannelPlugin(pluginID: String, config: [String: String]) async throws {
        struct Body: Encodable {
            let pluginID: String
            let config: [String: String]
            enum CodingKeys: String, CodingKey {
                case pluginID = "plugin_id"
                case config
            }
        }
        let _: CoworkEmpty = try await request("POST", path: "api/channel/plugins/enable", body: Body(pluginID: pluginID, config: config))
    }

    func disableChannelPlugin(pluginID: String) async throws {
        struct Body: Encodable {
            let pluginID: String
            enum CodingKeys: String, CodingKey { case pluginID = "plugin_id" }
        }
        let _: CoworkEmpty = try await request("POST", path: "api/channel/plugins/disable", body: Body(pluginID: pluginID))
    }

    func testChannelPlugin(pluginID: String, token: String) async throws -> CoworkChannelTestResult {
        struct Body: Encodable {
            let pluginID: String
            let token: String
            enum CodingKeys: String, CodingKey {
                case pluginID = "plugin_id"
                case token
            }
        }
        return try await request("POST", path: "api/channel/plugins/test", body: Body(pluginID: pluginID, token: token))
    }

    func listChannelPairings() async throws -> [CoworkChannelPairing] {
        try await request("GET", path: "api/channel/pairings")
    }

    func approveChannelPairing(code: String) async throws {
        struct Body: Encodable { let code: String }
        let _: CoworkEmpty = try await request("POST", path: "api/channel/pairings/approve", body: Body(code: code))
    }

    func rejectChannelPairing(code: String) async throws {
        struct Body: Encodable { let code: String }
        let _: CoworkEmpty = try await request("POST", path: "api/channel/pairings/reject", body: Body(code: code))
    }

    func listChannelUsers() async throws -> [CoworkChannelUser] {
        try await request("GET", path: "api/channel/users")
    }

    func revokeChannelUser(userID: String) async throws {
        struct Body: Encodable {
            let userID: String
            enum CodingKeys: String, CodingKey { case userID = "user_id" }
        }
        let _: CoworkEmpty = try await request("POST", path: "api/channel/users/revoke", body: Body(userID: userID))
    }
}
