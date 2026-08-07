import Foundation

/// Parses common blocklist text formats (hosts, plain domain, AdBlock-style rules).
enum BlocklistFeedParser {
    private static let ignoredHosts: Set<String> = [
        "localhost", "0.0.0.0", "127.0.0.1", "broadcasthost", "::1"
    ]

    static func domains(from text: String) -> Set<String> {
        var result = Set<String>()
        result.reserveCapacity(50_000)

        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let domain = domain(from: rawLine) else { continue }
            result.insert(domain)
        }
        return result
    }

    private static func domain(from rawLine: Substring) -> String? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") {
            return nil
        }

        let token = primaryToken(in: line)
        guard !token.isEmpty else { return nil }

        var host = normalizeRuleToken(token)
        host = host.lowercased()

        if host.contains("/") || ignoredHosts.contains(host) || host.isEmpty {
            return nil
        }
        return host
    }

    private static func primaryToken(in line: String) -> String {
        let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = columns.first else { return "" }

        if columns.count >= 2, isHostsFileAddress(first) {
            return columns[1]
        }
        return columns.last ?? first
    }

    private static func isHostsFileAddress(_ value: String) -> Bool {
        value == "0.0.0.0" || value == "127.0.0.1" || value == "::1"
    }

    private static func normalizeRuleToken(_ token: String) -> String {
        guard token.hasPrefix("||") else { return token }
        let body = token.dropFirst(2)
        if let separator = body.firstIndex(of: "^") {
            return String(body[..<separator])
        }
        return String(body)
    }
}
