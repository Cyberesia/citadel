import Foundation

/// Citadel-native rule evaluation engine.
/// Wire types (`Rule`, `Connection`, `AppMode`) stay Codable-compatible with SharedRuleBridge / XPC.
public struct FirewallRuleEvaluator: Sendable {
    public init() {}

    public func decision(
        for connection: Connection,
        rules: [Rule],
        defaultMode: AppMode,
        now: Date = Date()
    ) -> RuleAction {
        let candidates = rules
            .filter { $0.enabled }
            .filter { rule in
                if let expires = rule.expiresAt, expires < now { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdAt > rhs.createdAt
            }

        for rule in candidates where matches(rule: rule, connection: connection) {
            return rule.action
        }

        switch defaultMode {
        case .alert: return .ask
        case .silentAllow: return .allow
        case .silentDeny: return .deny
        }
    }

    public func matches(rule: Rule, connection: Connection) -> Bool {
        if rule.direction != .any && rule.direction != connection.direction {
            return false
        }
        if !processMatches(rule: rule, connection: connection) {
            return false
        }
        if let port = rule.remotePort, port != 0, connection.remotePort != port {
            return false
        }
        if let host = rule.remoteHost, !host.isEmpty {
            if !hostMatches(pattern: host, host: connection.remoteHost) {
                return false
            }
        }
        if let ip = rule.remoteIP, !ip.isEmpty {
            if !ipMatches(pattern: ip, ip: connection.remoteIP) {
                return false
            }
        }
        return true
    }

    // MARK: - Process

    private func processMatches(rule: Rule, connection: Connection) -> Bool {
        if rule.requiresSignature {
            guard connection.signingStatus == .signedValid else { return false }
        }
        if let team = rule.codeTeamID, !team.isEmpty {
            guard connection.codeTeamID == team else { return false }
        }
        if let bundleID = rule.processBundleId, !bundleID.isEmpty {
            return (connection.processBundleId ?? "") == bundleID
        }
        if let path = rule.processPath, !path.isEmpty {
            return connection.processPath == path || connection.processPath.hasPrefix(path)
        }
        if let name = rule.processName, !name.isEmpty {
            // Name-only rules (e.g. Cowork agent policy) must not match everything.
            return connection.processName.caseInsensitiveCompare(name) == .orderedSame
        }
        // Team-only rule (no bundle/path/name) already checked above.
        if let team = rule.codeTeamID, !team.isEmpty {
            return true
        }
        return true
    }

    // MARK: - Host / IP

    public func hostMatches(pattern: String, host: String) -> Bool {
        let pattern = pattern.lowercased()
        let host = host.lowercased()
        if pattern == host { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host == suffix || host.hasSuffix("." + suffix)
        }
        if pattern.hasPrefix(".") {
            let suffix = String(pattern.dropFirst())
            return host == suffix || host.hasSuffix("." + suffix) || host.hasSuffix(suffix)
        }
        return false
    }

    public func ipMatches(pattern: String, ip: String) -> Bool {
        if pattern == ip { return true }
        if pattern.contains("/") {
            return cidrContains(cidr: pattern, ip: ip)
        }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(2))
            return ip.hasPrefix(prefix + ".")
        }
        return false
    }

    private func cidrContains(cidr: String, ip: String) -> Bool {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let bits = Int(parts[1]), (0...32).contains(bits) else { return false }
        guard let network = ipv4ToUInt32(String(parts[0])), let address = ipv4ToUInt32(ip) else {
            return false
        }
        let mask: UInt32 = bits == 0 ? 0 : UInt32.max << (32 - bits)
        return (network & mask) == (address & mask)
    }

    private func ipv4ToUInt32(_ string: String) -> UInt32? {
        let octets = string.split(separator: ".")
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for octet in octets {
            guard let n = UInt32(octet), n < 256 else { return nil }
            value = (value << 8) | n
        }
        return value
    }
}

/// Compatibility façade — prefer `FirewallRuleEvaluator` in new code.
public struct RuleMatcher: Sendable {
    private let evaluator = FirewallRuleEvaluator()

    public init() {}

    public func decision(for c: Connection, rules: [Rule], defaultMode: AppMode) -> RuleAction {
        evaluator.decision(for: c, rules: rules, defaultMode: defaultMode)
    }

    public func matches(rule r: Rule, connection c: Connection) -> Bool {
        evaluator.matches(rule: r, connection: c)
    }

    public func hostMatches(pattern: String, host: String) -> Bool {
        evaluator.hostMatches(pattern: pattern, host: host)
    }

    public func ipMatches(pattern: String, ip: String) -> Bool {
        evaluator.ipMatches(pattern: pattern, ip: ip)
    }
}
