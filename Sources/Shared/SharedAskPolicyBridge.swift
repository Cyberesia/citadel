import Foundation

/// App-group preference for Network Extension ask-timeout behaviour.
public enum SharedAskPolicyBridge {
    public struct Snapshot: Codable, Sendable {
        public var timeoutDeny: Bool
        public var updatedAt: Date

        public init(timeoutDeny: Bool, updatedAt: Date = Date()) {
            self.timeoutDeny = timeoutDeny
            self.updatedAt = updatedAt
        }
    }

    private static var fileURL: URL? {
        SharedRuleBridge.containerURL?.appendingPathComponent("ask-policy.json")
    }

    public static func write(timeoutDeny: Bool) {
        guard let url = fileURL else { return }
        let snap = Snapshot(timeoutDeny: timeoutDeny)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read() -> Snapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(timeoutDeny: true)
        }
        return snap
    }
}
