import Foundation

/// Privileged `pfctl` anchor manager for Citadel (anchor name is a frozen contract: `citadel`).
final class PFManager: @unchecked Sendable {
    static let anchorName = "citadel"
    private let anchorPath = "/etc/pf.anchors/citadel"
    private let pfctl = "/sbin/pfctl"
    private let queue = DispatchQueue(label: "com.citadel.firewall.pf")
    private var loaded = false

    var isLoaded: Bool { loaded }

    func install() throws {
        try ensureMainConfLoadsAnchor()
        try writeAnchor(rules: [])
        try run(pfctl, ["-E"])
        try loadAnchor()
        loaded = true
    }

    func uninstall() throws {
        _ = try? run(pfctl, ["-a", Self.anchorName, "-F", "all"])
        _ = try? run(pfctl, ["-a", Self.anchorName, "-f", "/dev/null"])
        loaded = false
    }

    func applyRules(_ rules: [Rule]) throws {
        try writeAnchor(rules: rules)
        try loadAnchor()
    }

    private func loadAnchor() throws {
        try run(pfctl, ["-a", Self.anchorName, "-f", anchorPath])
    }

    private func writeAnchor(rules: [Rule]) throws {
        var lines: [String] = [
            "# Citadel pf anchor — auto-generated. Do not edit.",
            "set block-policy drop",
            "set skip on lo0"
        ]

        let deny = rules.filter { $0.action == .deny && $0.enabled }
        let allow = rules.filter { $0.action == .allow && $0.enabled }
        for rule in deny {
            if let line = pfRuleLine(rule, verb: "block") { lines.append(line) }
        }
        for rule in allow {
            if let line = pfRuleLine(rule, verb: "pass") { lines.append(line) }
        }

        try (lines.joined(separator: "\n") + "\n")
            .write(toFile: anchorPath, atomically: true, encoding: .utf8)
    }

    private func pfRuleLine(_ rule: Rule, verb: String) -> String? {
        let dir: String
        switch rule.direction {
        case .incoming: dir = "in"
        case .outgoing: dir = "out"
        case .any: dir = ""
        }

        var line = "\(verb) \(dir) quick".trimmingCharacters(in: .whitespaces) + " "
        line += "proto { tcp udp } "

        if let ip = rule.remoteIP, !ip.isEmpty {
            line += "to \(ip) "
        } else if let host = rule.remoteHost, !host.isEmpty {
            line += "to \(host) "
        }
        if let port = rule.remotePort, port > 0 {
            line += "port \(port) "
        }

        let hasTarget = !(rule.remoteIP?.isEmpty ?? true)
            || !(rule.remoteHost?.isEmpty ?? true)
            || (rule.remotePort ?? 0) != 0
        guard hasTarget else { return nil }
        return line.trimmingCharacters(in: .whitespaces)
    }

    private func ensureMainConfLoadsAnchor() throws {
        let path = "/etc/pf.conf"
        guard let original = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        if original.contains("anchor \"citadel\"") { return }

        var lines = original.components(separatedBy: "\n")
        lines.append("anchor \"citadel\"")
        lines.append("load anchor \"citadel\" from \"/etc/pf.anchors/citadel\"")

        let backup = path + ".citadel.bak"
        if !FileManager.default.fileExists(atPath: backup) {
            try? original.write(toFile: backup, atomically: true, encoding: .utf8)
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func run(_ executable: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            PSLog.error(PSLog.pf, "\(executable) \(args.joined(separator: " ")) rc=\(process.terminationStatus) \(err)")
            throw NSError(
                domain: "PFManager",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? out : err]
            )
        }
        return out
    }
}
