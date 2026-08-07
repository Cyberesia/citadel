import Foundation

/// Which provider rules to apply when curating MCP tool schemas.
enum CoworkMcpToolProfile: Equatable {
    case openAICompatible
    case anthropic
    case gemini
    case localPermissive

    static func from(platform: String) -> CoworkMcpToolProfile {
        switch platform.lowercased() {
        case "anthropic":
            return .anthropic
        case "gemini", "google":
            return .gemini
        case "ollama":
            return .localPermissive
        default:
            return .openAICompatible
        }
    }
}

/// Cursor-style MCP curation: filter servers/tools before CoworkCore forwards schemas to cloud APIs.
enum CoworkMcpCurator {
    /// Cloud APIs reject large bundled tool lists; keep a conservative cap.
    static let cloudMaxToolsPerSession = 32
    static let cloudMaxSchemaBytesPerTool = 6_144

    /// Servers that often expose dozens of browser tools with heavy JSON Schema.
    static let heavyServerNames: Set<String> = [
        CoworkMcpBootstrap.chromeName,
        "chrome_devtools",
        "chrome-devtools-mcp",
    ]

    struct ServerAssessment: Equatable {
        let serverID: String
        let serverName: String
        let isCompatible: Bool
        let usableToolCount: Int
        let totalToolCount: Int
        let skipReason: String?
    }

    static func assess(server: CoworkMcpServer, profile: CoworkMcpToolProfile) -> ServerAssessment {
        let tools = server.tools ?? []
        if tools.isEmpty {
            return ServerAssessment(
                serverID: server.id,
                serverName: server.name,
                isCompatible: true,
                usableToolCount: 0,
                totalToolCount: 0,
                skipReason: nil
            )
        }

        var usable = 0
        for tool in tools {
            guard isToolCompatible(tool, profile: profile) else { continue }
            usable += 1
        }

        if usable == 0 {
            return ServerAssessment(
                serverID: server.id,
                serverName: server.name,
                isCompatible: false,
                usableToolCount: 0,
                totalToolCount: tools.count,
                skipReason: "incompatible tool schemas"
            )
        }

        if profile != .localPermissive, tools.count > cloudMaxToolsPerSession {
            return ServerAssessment(
                serverID: server.id,
                serverName: server.name,
                isCompatible: false,
                usableToolCount: usable,
                totalToolCount: tools.count,
                skipReason: "too many tools (\(tools.count))"
            )
        }

        return ServerAssessment(
            serverID: server.id,
            serverName: server.name,
            isCompatible: true,
            usableToolCount: usable,
            totalToolCount: tools.count,
            skipReason: nil
        )
    }

    static func isToolCompatible(_ tool: CoworkMcpTool, profile: CoworkMcpToolProfile) -> Bool {
        guard profile != .localPermissive else { return true }
        guard let schema = tool.inputSchema else { return true }
        guard CoworkMcpToolSchemaSanitizer.isUsableAfterSanitization(schema, profile: profile) else {
            return false
        }
        if let sanitized = CoworkMcpToolSchemaSanitizer.sanitize(schema, profile: profile),
           CoworkMcpToolSchemaSanitizer.serializedByteCount(sanitized) > cloudMaxSchemaBytesPerTool {
            return false
        }
        return true
    }

    /// Default MCP selection for a provider (replaces blunt "MCP off" for cloud).
    static func defaultSelectedIDs(
        servers: [CoworkMcpServer],
        profile: CoworkMcpToolProfile
    ) -> Set<String> {
        curatedIDs(
            servers: servers,
            userSelected: [],
            profile: profile,
            preferDefaults: true
        )
    }

    /// Apply curation to the user's MCP picker selection before send.
    static func curatedIDs(
        servers: [CoworkMcpServer],
        userSelected: Set<String>,
        profile: CoworkMcpToolProfile,
        preferDefaults: Bool = false
    ) -> Set<String> {
        let enabled = servers.filter(\.enabled)
        let candidates: [CoworkMcpServer]
        if userSelected.isEmpty, preferDefaults {
            candidates = enabled.filter { !isHeavyServer($0) }
        } else if userSelected.isEmpty {
            candidates = []
        } else {
            candidates = enabled.filter { userSelected.contains($0.id) }
        }

        var picked: [CoworkMcpServer] = []
        var toolBudget = profile == .localPermissive ? Int.max : cloudMaxToolsPerSession

        for server in candidates {
            let assessment = assess(server: server, profile: profile)
            guard assessment.isCompatible else { continue }
            let count = max(assessment.usableToolCount, assessment.totalToolCount)
            if profile != .localPermissive, count > toolBudget, !picked.isEmpty {
                continue
            }
            picked.append(server)
            if profile != .localPermissive {
                toolBudget = max(0, toolBudget - count)
            }
        }

        return Set(picked.map(\.id))
    }

    static func isHeavyServer(_ server: CoworkMcpServer) -> Bool {
        let normalized = server.name.lowercased()
        return heavyServerNames.contains(normalized)
            || normalized.contains("chrome-devtools")
            || normalized.contains("devtools")
    }

    static func droppedServerSummary(
        servers: [CoworkMcpServer],
        before: Set<String>,
        after: Set<String>,
        profile: CoworkMcpToolProfile
    ) -> String? {
        let removed = before.subtracting(after)
        guard !removed.isEmpty else { return nil }
        let names = servers
            .filter { removed.contains($0.id) }
            .map(\.name)
        guard !names.isEmpty else { return nil }
        if profile == .localPermissive { return nil }
        return names.joined(separator: ", ")
    }
}
