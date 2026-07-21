import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Firewall control plane (rules / mode / alerts / helper)
    // GUI telemetry (rates, process list) is owned by Sentinel and mirrored in.
    @Published var mode: AppMode = .alert
    @Published var connections: [Connection] = []
    @Published var rules: [Rule] = []
    @Published var blocklists: [BlocklistInfo] = []
    @Published var profiles: [Profile] = []
    @Published var activeProfile: String = "default"
    @Published var trafficHistory: [TrafficSample] = []
    @Published var currentIn: Int64 = 0
    @Published var currentOut: Int64 = 0
    @Published var totalIn: Int64 = 0
    @Published var totalOut: Int64 = 0
    @Published var deniedCount: Int = 0
    @Published var unconfirmedCount: Int = 0
    @Published var incomingCount: Int = 0
    @Published var pendingAlerts: [PendingAlert] = []
    @Published var helperConnected: Bool = false
    @Published var pfctlEnabled: Bool = false
    @Published var dnsProxyEnabled: Bool = false
    @Published var logs: [LogEntry] = []
    @Published var topProcesses: [ProcessStats] = []
    @Published var topDomains: [DomainStats] = []
    @Published var topCountries: [CountryStats] = []
    @Published var searchQuery: String = ""
    @Published var isDemoMode: Bool = false
    @Published var isLocalMonitoring: Bool = false

    /// App-wide font scale (1.0 = default). Persisted and mirrored to `AppFontScale`
    /// so every `Font.ps(...)` call renders at the chosen size across all windows.
    @Published var fontScale: CGFloat = AppFontScale.current {
        didSet {
            AppFontScale.current = fontScale
            UserDefaults.standard.set(Double(fontScale), forKey: "appFontScale")
        }
    }

    let helper = HelperClient()
    private let store: RuleStore? = {
        try? RuleStore(path: AppConstants.supportDir.appendingPathComponent("ui-cache.sqlite").path)
    }()

    /// When true, GUI rates/process list come from Sentinel (not helper NetMonitor / local lsof).
    private(set) var sentinelOwnsTelemetry = false

    struct PendingAlert: Identifiable {
        let id = UUID()
        let connection: Connection
        let reply: (Bool, Bool) -> Void
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: String
        let message: String
    }

    struct ProcessStats: Identifiable {
        let id: String
        let name: String
        let bytesIn: Int64
        let bytesOut: Int64
        let bytesInRate: Int64
        let bytesOutRate: Int64
        let icon: NSImage?
        let connectionCount: Int
        var total: Int64 { bytesIn + bytesOut }
        var rateTotal: Int64 { bytesInRate + bytesOutRate }
    }

    struct DomainStats: Identifiable {
        let id: String
        let domain: String
        let bytesIn: Int64
        let bytesOut: Int64
        let connectionCount: Int
        var total: Int64 { bytesIn + bytesOut }
    }

    struct CountryStats: Identifiable {
        let id: String
        let country: String
        let countryCode: String
        let bytesIn: Int64
        let bytesOut: Int64
        let connectionCount: Int
        var total: Int64 { bytesIn + bytesOut }
    }

    init() {
        helper.state = self
        AppFontScale.current = fontScale
    }

    func bootstrap() {
        helper.startMonitoring()
        helper.installPF()
        refreshRules()
    }

    /// Sentinel is the sole GUI telemetry source (menubar + rates). Call once at launch.
    func adoptSentinelTelemetry() {
        sentinelOwnsTelemetry = true
        isLocalMonitoring = false
    }

    /// Push live Sentinel rates + process rollup into AppState for menubar / popover.
    func applySentinelTelemetry(
        rateIn: Int64,
        rateOut: Int64,
        processes: [ProcessStats]
    ) {
        sentinelOwnsTelemetry = true
        currentIn = rateIn
        currentOut = rateOut
        totalIn &+= rateIn
        totalOut &+= rateOut
        trafficHistory.append(TrafficSample(timestamp: Date(), bytesIn: rateIn, bytesOut: rateOut))
        if trafficHistory.count > 600 {
            trafficHistory.removeFirst(trafficHistory.count - 600)
        }
        topProcesses = processes
    }

    func refreshRules() {
        helper.listRules { [weak self] rules in
            guard let self else { return }
            self.rules = rules
            self.syncSharedRules()
        }
    }

    /// Mirror the active rules + mode into the app-group container so the
    /// Network System Extension (which can't read the helper DB) can enforce them.
    func syncSharedRules() {
        SharedRuleBridge.write(mode: mode, rules: rules)
    }

    func setMode(_ m: AppMode) {
        mode = m
        helper.setMode(m)
        syncSharedRules()
    }

    /// Upsert a rule into helper DB + UI cache + SharedRuleBridge (NE).
    func upsertRule(_ rule: Rule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
        helper.addRule(rule)
        syncSharedRules()
        refreshRules()
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        helper.removeRule(id: id)
        syncSharedRules()
        refreshRules()
    }

    // MARK: - Cowork agent firewall policy

    /// Rules targeting the Cowork agent backend process.
    private var agentRules: [Rule] {
        rules.filter { rule in
            rule.scope == .process && (rule.processName.map { CitadelAgentProcess.isAgent(processName: $0) } ?? false)
        }
    }

    /// Effective policy for agent traffic (nil = no dedicated rule, global mode applies).
    var agentFirewallPolicy: RuleAction? {
        agentRules.first(where: \.enabled)?.action
    }

    /// Replaces any agent-process rule with the requested action (nil removes the policy).
    func setAgentFirewallPolicy(_ action: RuleAction?) {
        for rule in agentRules {
            helper.removeRule(id: rule.id)
            rules.removeAll { $0.id == rule.id }
        }
        if let action {
            let rule = Rule(
                processName: "coworkcore",
                direction: .outgoing,
                action: action,
                scope: .process,
                priority: 50,
                profile: activeProfile,
                notes: "Keep agent policy"
            )
            rules.append(rule)
            helper.addRule(rule)
        }
        syncSharedRules()
        refreshRules()
    }

    func updateConnections(_ conns: [Connection]) {
        connections = conns
        deniedCount = connections.filter { $0.status == .denied }.count
        incomingCount = connections.filter { $0.direction == .incoming }.count
        unconfirmedCount = connections.filter { $0.status == .pending }.count
        // Process/domain rollups for the menubar come from Sentinel telemetry.
    }

    /// Classic GUI local `NetMonitor` removed — Sentinel owns unprivileged telemetry.
    func startLocalMonitoringIfNeeded() {
        isLocalMonitoring = false
    }

    func stopLocalMonitoring() {
        isLocalMonitoring = false
    }

    func loadDemoData() {
        // Prefer Sentinel demo; AppState only clears classic flags.
        isDemoMode = true
        stopLocalMonitoring()
    }

    func appendSample(_ s: TrafficSample) {
        // When Sentinel owns the menubar, ignore helper rate pushes to avoid double history.
        guard !sentinelOwnsTelemetry else { return }
        trafficHistory.append(s)
        if trafficHistory.count > 600 { trafficHistory.removeFirst(trafficHistory.count - 600) }
        currentIn = s.bytesIn
        currentOut = s.bytesOut
        totalIn &+= s.bytesIn
        totalOut &+= s.bytesOut
    }

    func presentAlert(for c: Connection, reply: @escaping (Bool, Bool) -> Void) {
        pendingAlerts.append(PendingAlert(connection: c, reply: reply))
    }

    func resolveAlert(_ alert: PendingAlert, allow: Bool, remember: Bool) {
        alert.reply(allow, remember)
        pendingAlerts.removeAll { $0.id == alert.id }
        if remember {
            let rule = Rule(
                processBundleId: alert.connection.processBundleId,
                processPath: alert.connection.processPath,
                processName: alert.connection.processName,
                remoteHost: alert.connection.remoteHost,
                remotePort: alert.connection.remotePort,
                direction: alert.connection.direction,
                action: allow ? .allow : .deny,
                scope: alert.connection.remoteHost.isEmpty ? .ip : .domain,
                priority: 100,
                profile: activeProfile,
                groupName: nil,
                notes: "Created from alert"
            )
            rules.append(rule)        // optimistic: extension sees it even if the helper is down
            helper.addRule(rule)
            syncSharedRules()
            refreshRules()
        }
    }

    func appendLog(level: String, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        logs.append(entry)
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }

}
