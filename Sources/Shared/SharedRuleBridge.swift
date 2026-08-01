import Foundation

/// App-group snapshot of active firewall mode and rules for CitadelNetExt.
///
/// The network extension cannot read the privileged helper database, so the GUI
/// publishes this JSON document whenever enforcement inputs change.
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

    private static let store = AppGroupJSONStore<Snapshot>(fileName: "filter-rules.json")

    public static var containerURL: URL? {
        store.fileURL?.deletingLastPathComponent()
    }

    public static func write(mode: AppMode, rules: [Rule]) {
        store.write(Snapshot(mode: mode, rules: rules))
    }

    public static func read() -> Snapshot {
        store.read(default: Snapshot(mode: .alert, rules: []))
    }
}
