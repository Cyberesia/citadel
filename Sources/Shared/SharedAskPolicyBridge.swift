import Foundation

/// App-group preference for how paused network-filter flows behave on timeout.
public enum SharedAskPolicyBridge {
    public struct Snapshot: Codable, Sendable {
        public var timeoutDeny: Bool
        public var updatedAt: Date

        public init(timeoutDeny: Bool, updatedAt: Date = Date()) {
            self.timeoutDeny = timeoutDeny
            self.updatedAt = updatedAt
        }
    }

    private static let store = AppGroupJSONStore<Snapshot>(fileName: "ask-policy.json")

    public static func write(timeoutDeny: Bool) {
        store.write(Snapshot(timeoutDeny: timeoutDeny))
    }

    public static func read() -> Snapshot {
        store.read(default: Snapshot(timeoutDeny: true))
    }
}
