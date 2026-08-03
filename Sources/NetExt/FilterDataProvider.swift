#if canImport(NetworkExtension)
import Foundation
import NetworkExtension

/// Citadel content-filter provider — evaluates socket flows against published rules.
final class FilterDataProvider: NEFilterDataProvider {
    private let evaluator = FirewallRuleEvaluator()
    private let workQueue = DispatchQueue(label: "com.citadel.firewall.netext.work")
    private lazy var flowArbiter = InteractiveFlowArbiter(
        timeout: 60,
        queue: workQueue,
        resumeFlow: { [weak self] flow, verdict in
            self?.resumeFlow(flow, with: verdict)
        }
    )

    private var publishedRules = SharedRuleBridge.Snapshot(mode: .alert, rules: [])
    private var snapshotTimer: DispatchSourceTimer?

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        IPCConnection.shared.startListener()
        refreshPublishedRules()
        startSnapshotWatcher()

        let settings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(settings, completionHandler: completionHandler)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        snapshotTimer?.cancel()
        snapshotTimer = nil
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow else {
            return .allow()
        }

        let connection = FilterSocketFlowMapper.connection(from: socketFlow)
        switch evaluator.decision(for: connection, rules: publishedRules.rules, defaultMode: publishedRules.mode) {
        case .allow:
            return .allow()
        case .deny:
            return .drop()
        case .ask:
            flowArbiter.resolve(flow: flow, connection: connection)
            return .pause()
        }
    }

    private func refreshPublishedRules() {
        publishedRules = SharedRuleBridge.read()
    }

    private func startSnapshotWatcher() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 2, repeating: .seconds(2))
        timer.setEventHandler { [weak self] in self?.refreshPublishedRules() }
        timer.resume()
        snapshotTimer = timer
    }
}
#endif
