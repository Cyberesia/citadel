#if canImport(NetworkExtension)
import Foundation
import NetworkExtension

/// Resolves paused filter flows by consulting the GUI over XPC, with timeout policy.
final class InteractiveFlowArbiter: @unchecked Sendable {
    private let timeout: TimeInterval
    private let queue: DispatchQueue
    private let resumeFlow: (NEFilterFlow, NEFilterNewFlowVerdict) -> Void

    init(
        timeout: TimeInterval,
        queue: DispatchQueue,
        resumeFlow: @escaping (NEFilterFlow, NEFilterNewFlowVerdict) -> Void
    ) {
        self.timeout = timeout
        self.queue = queue
        self.resumeFlow = resumeFlow
    }

    func resolve(flow: NEFilterFlow, connection: Connection) {
        guard let payload = try? JSONEncoder().encode(connection) else {
            resumeFlow(flow, .allow())
            return
        }

        var finished = false
        let lock = NSLock()
        let finish: (NEFilterNewFlowVerdict) -> Void = { [weak self] verdict in
            lock.lock()
            defer { lock.unlock() }
            guard let self, !finished else { return }
            finished = true
            self.resumeFlow(flow, verdict)
        }

        let delivered = IPCConnection.shared.promptUser(flowJSON: payload) { allow, _ in
            finish(allow ? .allow() : .drop())
        }

        guard delivered else {
            finish(.allow())
            return
        }

        let denyWhenTimedOut = SharedAskPolicyBridge.read().timeoutDeny
        queue.asyncAfter(deadline: .now() + timeout) {
            finish(denyWhenTimedOut ? .drop() : .allow())
        }
    }
}
#endif
