import Foundation

enum CoworkMcpBootstrap {
    static let imageGenName = "citadel-image-generation"
    static let chromeName = "chrome-devtools"

    static func serversToImport(providers: [CoworkProvider]) -> [CoworkMcpImportServer] {
        var servers: [CoworkMcpImportServer] = [chromeDevtoolsServer()]
        if let imageGen = imageGenerationServer(providers: providers) {
            servers.append(imageGen)
        }
        return servers
    }

    private static func chromeDevtoolsServer() -> CoworkMcpImportServer {
        let config: [String: Any] = [
            "command": "npx",
            "args": ["-y", "chrome-devtools-mcp@latest"],
        ]
        let json = jsonString(mcpServers: [chromeName: config])
        return CoworkMcpImportServer(
            name: chromeName,
            description: "Browser automation via Chrome DevTools MCP",
            transport: CoworkMcpTransport(type: "stdio", command: "npx", args: ["-y", "chrome-devtools-mcp@latest"], url: nil),
            originalJSON: json,
            builtin: true
        )
    }

    private static func imageGenerationServer(providers: [CoworkProvider]) -> CoworkMcpImportServer? {
        guard let env = resolveImageGenEnv(providers: providers) else { return nil }
        guard let node = resolveNodePath() else { return nil }
        // CoworkCore bundles the script when available; fall back to npx wrapper path in managed-resources later.
        let scriptCandidates = [
            bundledImageGenScriptPath(),
            "/usr/local/bin/citadel-image-gen-mcp.js",
        ].compactMap { $0 }
        guard let script = scriptCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        var config: [String: Any] = ["command": node, "args": [script], "env": env]
        let json = jsonString(mcpServers: [imageGenName: config])
        return CoworkMcpImportServer(
            name: imageGenName,
            description: "Image generation via your configured model provider",
            transport: CoworkMcpTransport(type: "stdio", command: node, args: [script], url: nil),
            originalJSON: json,
            builtin: true
        )
    }

    static func resolveImageGenEnv(providers: [CoworkProvider]) -> [String: String]? {
        let imageKeywords = ["flux", "image", "dall", "gpt-image", "imagen", "vision"]
        for provider in providers {
            for model in provider.models {
                let lower = model.lowercased()
                if imageKeywords.contains(where: { lower.contains($0) }) {
                    return [
                        "AIONUI_IMG_PROVIDER_ID": provider.id,
                        "AIONUI_IMG_PLATFORM": provider.platform,
                        "AIONUI_IMG_BASE_URL": CoworkOllamaModelsAPI.normalizedChatBaseURL(provider.baseURL),
                        "AIONUI_IMG_API_KEY": provider.apiKey,
                        "AIONUI_IMG_MODEL": model,
                    ]
                }
            }
        }
        if let provider = providers.first, let model = provider.models.first {
            return [
                "AIONUI_IMG_PROVIDER_ID": provider.id,
                "AIONUI_IMG_PLATFORM": provider.platform,
                "AIONUI_IMG_BASE_URL": CoworkOllamaModelsAPI.normalizedChatBaseURL(provider.baseURL),
                "AIONUI_IMG_API_KEY": provider.apiKey,
                "AIONUI_IMG_MODEL": model,
            ]
        }
        return nil
    }

    private static func bundledImageGenScriptPath() -> String? {
        guard let resource = Bundle.main.resourceURL else { return nil }
        let path = resource
            .appendingPathComponent("coworkcore-bundled/darwin-arm64/managed-resources/mcp/builtin-mcp-image-gen.js")
            .path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func resolveNodePath() -> String? {
        let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func jsonString(mcpServers: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["mcpServers": mcpServers], options: [.prettyPrinted])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
