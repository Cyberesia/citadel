import Foundation

/// Manages Citadel's dedicated `pfctl` anchor without touching unrelated PF rules.
final class PFManager: @unchecked Sendable {
    static let anchorName = "citadel"

    private let anchorFile = "/etc/pf.anchors/citadel"
    private let pfctlPath = "/sbin/pfctl"
    private let mainConfigPath = "/etc/pf.conf"
    private let syncQueue = DispatchQueue(label: "com.citadel.firewall.pf")
    private var anchorInstalled = false

    var isLoaded: Bool { anchorInstalled }

    func install() throws {
        try syncQueue.sync {
            try ensureAnchorReferencedInMainConfig()
            try writeAnchor(rules: [])
            try PFCommandExecutor.run(executable: pfctlPath, arguments: ["-E"])
            try reloadAnchor()
            anchorInstalled = true
        }
    }

    func uninstall() throws {
        try syncQueue.sync {
            _ = try? PFCommandExecutor.run(executable: pfctlPath, arguments: ["-a", Self.anchorName, "-F", "all"])
            _ = try? PFCommandExecutor.run(executable: pfctlPath, arguments: ["-a", Self.anchorName, "-f", "/dev/null"])
            anchorInstalled = false
        }
    }

    func applyRules(_ rules: [Rule]) throws {
        try syncQueue.sync {
            try writeAnchor(rules: rules)
            try reloadAnchor()
        }
    }

    // MARK: - Anchor IO

    private func writeAnchor(rules: [Rule]) throws {
        let body = PFRuleTranslator.anchorBody(for: rules)
        try body.write(toFile: anchorFile, atomically: true, encoding: .utf8)
    }

    private func reloadAnchor() throws {
        try PFCommandExecutor.run(
            executable: pfctlPath,
            arguments: ["-a", Self.anchorName, "-f", anchorFile]
        )
    }

    private func ensureAnchorReferencedInMainConfig() throws {
        guard let original = try? String(contentsOfFile: mainConfigPath, encoding: .utf8) else {
            return
        }
        guard !original.contains("anchor \"\(Self.anchorName)\"") else { return }

        var lines = original.components(separatedBy: "\n")
        lines.append("anchor \"\(Self.anchorName)\"")
        lines.append("load anchor \"\(Self.anchorName)\" from \"\(anchorFile)\"")

        let backupPath = mainConfigPath + ".citadel.bak"
        if !FileManager.default.fileExists(atPath: backupPath) {
            try? original.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        try lines.joined(separator: "\n").write(toFile: mainConfigPath, atomically: true, encoding: .utf8)
    }
}
