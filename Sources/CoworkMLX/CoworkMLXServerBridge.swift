import Foundation

/// Starts native in-process MLX and exposes an OpenAI-compatible endpoint for CoworkCore.
enum CoworkMLXServerBridge {
    static let defaultPort = 8765

    static var isRunning: Bool {
        get async {
            await CoworkMLXOpenAIServer.shared.isRunning
        }
    }

    static func chatBaseURL() -> String {
        "http://127.0.0.1:\(defaultPort)/v1"
    }

    static func isMLXAvailable() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static func startIfNeeded(
        repoID: String,
        status: (@MainActor (String?) -> Void)? = nil
    ) async throws {
        guard isMLXAvailable() else {
            throw CoworkMLXBridgeError.unsupportedArchitecture
        }
        try await CoworkMLXOpenAIServer.shared.start(
            port: defaultPort,
            repoID: repoID,
            status: status
        )
    }

    static func stop() async {
        await CoworkMLXOpenAIServer.shared.stop()
        await CoworkMLXNativeRuntime.shared.unload()
    }
}
