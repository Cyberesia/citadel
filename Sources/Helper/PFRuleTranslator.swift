import Foundation

/// Translates Citadel `Rule` records into OpenBSD PF anchor directives.
enum PFRuleTranslator {
    static func anchorBody(for rules: [Rule]) -> String {
        var lines = [
            "# Citadel packet-filter anchor — generated automatically.",
            "set block-policy drop",
            "set skip on lo0"
        ]

        let active = rules.filter(\.enabled)
        for rule in active where rule.action == .deny {
            if let line = directive(for: rule, verb: "block") {
                lines.append(line)
            }
        }
        for rule in active where rule.action == .allow {
            if let line = directive(for: rule, verb: "pass") {
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func directive(for rule: Rule, verb: String) -> String? {
        guard hasNetworkTarget(rule) else { return nil }

        let directionToken: String
        switch rule.direction {
        case .incoming: directionToken = "in"
        case .outgoing: directionToken = "out"
        case .any: directionToken = ""
        }

        var parts = [verb]
        if !directionToken.isEmpty { parts.append(directionToken) }
        parts.append("quick")
        parts.append("proto { tcp udp }")

        if let ip = rule.remoteIP, !ip.isEmpty {
            parts.append("to \(ip)")
        } else if let host = rule.remoteHost, !host.isEmpty {
            parts.append("to \(host)")
        }

        if let port = rule.remotePort, port > 0 {
            parts.append("port \(port)")
        }

        return parts.joined(separator: " ")
    }

    private static func hasNetworkTarget(_ rule: Rule) -> Bool {
        !(rule.remoteIP?.isEmpty ?? true)
            || !(rule.remoteHost?.isEmpty ?? true)
            || (rule.remotePort ?? 0) > 0
    }
}
