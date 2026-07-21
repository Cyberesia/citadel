import Foundation
import Combine

/// Sentinel firewall façade — delegates to `AppState` so Network Extension
/// SharedRuleBridge stays in sync. No second XPC client (alerts stay on AppState).
@MainActor
final class SentinelFirewallBridge: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var mode: AppMode = .alert
    @Published var pendingAlerts: [SentinelAlert] = []
    @Published private(set) var rules: [Rule] = []

    weak var viewModel: SentinelViewModel?
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    func bind(to state: AppState) {
        appState = state
        cancellables.removeAll()

        state.$helperConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.connected = value
            }
            .store(in: &cancellables)

        state.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.mode = value
            }
            .store(in: &cancellables)

        state.$rules
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.rules = value
            }
            .store(in: &cancellables)

        connected = state.helperConnected
        mode = state.mode
        rules = state.rules
    }

    func connect() {
        appState?.refreshRules()
    }

    func setMode(_ m: AppMode) {
        appState?.setMode(m)
        mode = m
    }

    func addRule(_ rule: Rule) {
        appState?.upsertRule(rule)
    }

    func removeRule(id: UUID) {
        appState?.removeRule(id: id)
    }

    func refreshRules() {
        appState?.refreshRules()
    }

    func allow(stream: NetworkStream, remember: Bool) {
        addRule(makeRule(from: stream, action: .allow, remember: remember))
    }

    func deny(stream: NetworkStream, remember: Bool) {
        addRule(makeRule(from: stream, action: .deny, remember: remember))
    }

    func resolveAlert(_ alert: SentinelAlert, allow: Bool, remember: Bool) {
        // Prefer AppState floating alert path; this is for any residual Sentinel queue.
        alert.reply(allow, remember)
        pendingAlerts.removeAll { $0.id == alert.id }
        if remember || !allow {
            let action: RuleAction = allow ? .allow : .deny
            addRule(makeRule(from: alert.stream, action: action, remember: remember))
        }
    }

    private func makeRule(from stream: NetworkStream, action: RuleAction, remember: Bool) -> Rule {
        Rule(
            processBundleId: stream.process.bundleID,
            processPath: stream.process.path.isEmpty ? nil : stream.process.path,
            processName: stream.process.name,
            remoteHost: stream.remoteHost.isEmpty ? nil : stream.remoteHost,
            remoteIP: stream.remoteIP.isEmpty ? nil : stream.remoteIP,
            remotePort: stream.remotePort == 0 ? nil : stream.remotePort,
            direction: .outgoing,
            action: action,
            scope: stream.remoteHost.isEmpty || NetworkStream.looksLikeIP(stream.remoteHost) ? .ip : .domain,
            priority: 100,
            notes: remember ? "Created from Sentinel" : "Temporary from Sentinel",
            temporary: !remember,
            expiresAt: remember ? nil : Date().addingTimeInterval(60 * 60)
        )
    }
}
