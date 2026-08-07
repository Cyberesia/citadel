import Foundation

// MARK: - WebUI remote access + auth (plan Phase 6)

struct CoworkAuthStatus: Decodable {
    let needsSetup: Bool?
    let isAuthenticated: Bool?
    let userCount: Int?

    enum CodingKeys: String, CodingKey {
        case needsSetup = "needs_setup"
        case isAuthenticated = "is_authenticated"
        case userCount = "user_count"
    }
}

struct CoworkWebUIPassword: Decodable {
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case newPassword = "new_password"
    }
}

struct CoworkWebUIQRToken: Decodable {
    let token: String
    let expiresAtMS: Double?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAtMS = "expires_at_ms"
    }
}

extension CoworkCoreClient {
    private struct CoworkEmpty: Decodable {}
    private struct CoworkEmptyBody: Encodable {}

    /// Raw status envelope (no `data` wrapper) — decode directly.
    func authStatus() async throws -> CoworkAuthStatus {
        try await request("GET", path: "api/auth/status")
    }

    /// Local-mode only: rotates the WebUI password and returns the generated secret.
    func webuiResetPassword() async throws -> CoworkWebUIPassword {
        try await request("POST", path: "api/webui/reset-password", body: CoworkEmptyBody())
    }

    func webuiChangeUsername(_ username: String) async throws -> String {
        struct Body: Encodable {
            let newUsername: String
            enum CodingKeys: String, CodingKey { case newUsername = "new_username" }
        }
        struct Result: Decodable { let username: String }
        let result: Result = try await request("POST", path: "api/webui/change-username", body: Body(newUsername: username))
        return result.username
    }

    func webuiChangePassword(_ password: String) async throws {
        struct Body: Encodable {
            let newPassword: String
            enum CodingKeys: String, CodingKey { case newPassword = "new_password" }
        }
        let _: CoworkEmpty = try await request("POST", path: "api/webui/change-password", body: Body(newPassword: password))
    }

    func webuiGenerateQRToken() async throws -> CoworkWebUIQRToken {
        try await request("POST", path: "api/webui/generate-qr-token", body: CoworkEmptyBody())
    }

    /// Session login used when the backend runs in remote (authenticated) mode.
    func login(username: String, password: String) async throws {
        struct Body: Encodable { let username: String; let password: String }
        // Prime the CSRF cookie before the first mutating call.
        _ = try? await authStatus()
        let _: CoworkEmpty = try await request("POST", path: "login", body: Body(username: username, password: password))
    }

    func logout() async throws {
        let _: CoworkEmpty = try await request("POST", path: "logout", body: CoworkEmptyBody())
    }
}
