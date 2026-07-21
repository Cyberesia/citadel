import Foundation

/// App-group mirror of active mode + rules for the Network System Extension.
///
/// The extension cannot read the helper SQLite DB, so the GUI writes this JSON
/// snapshot whenever mode/rules change. Codable shape is a frozen wire contract.
public enum SharedRuleBridge {
    public struct Snapshot: Codable, Sendable {
        public var mode: AppMode
        public var rules: [Rule]
        public var updatedAt: Date

        public init(mode: AppMode, rules: [Rule], updatedAt: Date = Date()) {
            self.mode = mode
            self.rules = rules
            self.updatedAt = updatedAt
        }
    }

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent("filter-rules.json")
    }

    public static func write(mode: AppMode, rules: [Rule]) {
        guard let url = fileURL else { return }
        let snap = Snapshot(mode: mode, rules: rules)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read() -> Snapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(mode: .alert, rules: [])
        }
        return snap
    }
}
