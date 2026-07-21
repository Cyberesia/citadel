import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Firewall control plane (rules / mode / alerts / helper)
    // GUI telemetry (rates, process list) is owned by Fortress and mirrored in.
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
    /// Network filter extension status — separate from privileged Helper.
    @Published var netExtStatus: NetExtProtectionStatus = .unknown
    @Published var pfctlEnabled: Bool = false
    @Published var dnsProxyEnabled: Bool = false
    @Published var useSystemDNS: Bool = UserDefaults.standard.object(forKey: "citadel.dns.system") as? Bool ?? true
    @Published var askTimeoutDeny: Bool = UserDefaults.standard.object(forKey: "citadel.ask.timeoutDeny") as? Bool ?? true
    @Published var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: "citadel.launchAtLogin")
    @Published var showAlertsOnAllSpaces: Bool = UserDefaults.standard.object(forKey: "citadel.alertsAllSpaces") as? Bool ?? true
    @Published var logs: [LogEntry] = []
    @Published var topProcesses: [ProcessStats] = []
    @Published var topDomains: [DomainStats] = []
    @Published var topCountries: [CountryStats] = []
    @Published var searchQuery: String = ""
    @Published var isDemoMode: Bool = false
    @Published var isLocalMonitoring: Bool = false
    @Published var connectionHistory: [Connection] = []
    @Published var showFortressHelp = false
    @Published var fortressHelpTopicID: String?

    enum NetExtProtectionStatus: String, Equatable {
        case unknown
        case unsupported
        case needsApproval
        case activating
        case active
        case inactive
        case failed
    }
    /// App-wide font scale (1.0 = default). Persisted and mirrored to `AppFontScale`
    /// so every `Font.ps(...)` call renders at the chosen size across all windows.
    @Published var fontScale: CGFloat = AppFontScale.current {
        didSet {
            AppFontScale.current = fontScale
            UserDefaults.standard.set(Double(fontScale), forKey: "appFontScale")
        }
    }

    let helper = HelperClient()
    let store: RuleStore? = {
        try? RuleStore(path: AppConstants.supportDir.appendingPathComponent("ui-cache.sqlite").path)
    }()

    /// When true, GUI rates/process list come from Fortress (not helper NetMonitor / local lsof).
    private(set) var fortressOwnsTelemetry = false

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
        refreshProfilesAndBlocklists()
        purgeExpiredRules()
        loadConnectionHistory()
        try? store?.purgeConnections(olderThan: Date().addingTimeInterval(-7 * 24 * 60 * 60))
    }

    func refreshProfilesAndBlocklists() {
        if let store {
            profiles = store.allProfiles()
            blocklists = store.allBlocklists()
            if let active = profiles.first(where: \.isActive)?.name {
                activeProfile = active
            }
        }
        helper.listBlocklists { [weak self] lists in
            guard let self, !lists.isEmpty else { return }
            self.blocklists = lists
        }
        helper.listProfiles { [weak self] profiles in
            guard let self, !profiles.isEmpty else { return }
            self.profiles = profiles
            if let active = profiles.first(where: \.isActive)?.name {
                self.activeProfile = active
            }
        }
    }

    func activateProfile(_ name: String) {
        activeProfile = name
        try? store?.setActiveProfile(name: name)
        helper.setActiveProfile(name)
        if let profile = profiles.first(where: { $0.name == name }) {
            setMode(profile.mode)
        }
        profiles = profiles.map { p in
            var copy = p
            copy.isActive = p.name == name
            return copy
        }
        refreshRules()
        syncSharedRules()
        appendLog(level: "info", message: "Profile activated: \(name)")
    }

    func setUseSystemDNS(_ enabled: Bool) {
        useSystemDNS = enabled
        UserDefaults.standard.set(enabled, forKey: "citadel.dns.system")
        if enabled {
            helper.installDNS()
        } else {
            helper.uninstallDNS()
        }
        dnsProxyEnabled = enabled
    }

    func setAskTimeoutDeny(_ deny: Bool) {
        askTimeoutDeny = deny
        UserDefaults.standard.set(deny, forKey: "citadel.ask.timeoutDeny")
        SharedAskPolicyBridge.write(timeoutDeny: deny)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        UserDefaults.standard.set(enabled, forKey: "citadel.launchAtLogin")
        LoginItemHelper.setEnabled(enabled)
    }

    func setShowAlertsOnAllSpaces(_ enabled: Bool) {
        showAlertsOnAllSpaces = enabled
        UserDefaults.standard.set(enabled, forKey: "citadel.alertsAllSpaces")
    }

    func purgeExpiredRules() {
        try? store?.purgeExpiredRules()
        helper.purgeExpiredRules()
        refreshRules()
    }

    func purgeSessionRulesOnQuit() {
        try? store?.purgeSessionRules()
        helper.purgeSessionRules()
        refreshRules()
        syncSharedRules()
    }

    func loadConnectionHistory(
        days: Int = 7,
        processName: String? = nil,
        hostQuery: String? = nil
    ) {
        let since = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        connectionHistory = store?.recentConnections(
            limit: 500,
            since: since,
            processName: processName,
            hostQuery: hostQuery
        ) ?? []
    }

    func recordHistoryConnection(_ c: Connection) {
        try? store?.recordConnection(c)
    }

    var protectionStatusLabel: String {
        switch netExtStatus {
        case .active:
            return helperConnected ? L10n.protectionActive : L10n.protectionFilterOnly
        case .needsApproval:
            return L10n.protectionNeedsApproval
        case .activating:
            return L10n.protectionActivating
        case .unsupported, .inactive, .failed, .unknown:
            return helperConnected ? L10n.protectionLocalMode : L10n.protectionLimited
        }
    }

    /// Fortress is the sole GUI telemetry source (menubar + rates). Call once at launch.
    func adoptFortressTelemetry() {
        fortressOwnsTelemetry = true
        isLocalMonitoring = false
    }

    /// Push live Fortress rates + process rollup into AppState for menubar / popover.
    func applyFortressTelemetry(
        rateIn: Int64,
        rateOut: Int64,
        processes: [ProcessStats]
    ) {
        fortressOwnsTelemetry = true
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
        // Process/domain rollups for the menubar come from Fortress telemetry.
    }

    /// Classic GUI local `NetMonitor` removed — Fortress owns unprivileged telemetry.
    func startLocalMonitoringIfNeeded() {
        isLocalMonitoring = false
    }

    func stopLocalMonitoring() {
        isLocalMonitoring = false
    }

    func loadDemoData() {
        // Prefer Fortress demo; AppState only clears classic flags.
        isDemoMode = true
        stopLocalMonitoring()
    }

    func appendSample(_ s: TrafficSample) {
        // When Fortress owns the menubar, ignore helper rate pushes to avoid double history.
        guard !fortressOwnsTelemetry else { return }
        trafficHistory.append(s)
        if trafficHistory.count > 600 { trafficHistory.removeFirst(trafficHistory.count - 600) }
        currentIn = s.bytesIn
        currentOut = s.bytesOut
        totalIn &+= s.bytesIn
        totalOut &+= s.bytesOut
    }

    func presentAlert(for c: Connection, reply: @escaping (Bool, Bool) -> Void) {
        var enriched = c
        if enriched.signingStatus == .unknown, !enriched.processPath.isEmpty {
            let snap = ProcessSigningIdentity.resolve(path: enriched.processPath)
            enriched.codeTeamID = snap.teamID
            enriched.signingStatus = snap.status
        }
        pendingAlerts.append(PendingAlert(connection: enriched, reply: reply))
    }

    func resolveAlert(
        _ alert: PendingAlert,
        allow: Bool,
        remember: Bool,
        scope: ConnectionAlertView.AlertScope = .thisHost,
        duration: ConnectionAlertView.AlertDuration = .forever
    ) {
        alert.reply(allow, remember)
        pendingAlerts.removeAll { $0.id == alert.id }
        guard remember || (!allow && duration != .forever) else { return }

        let c = alert.connection
        var remoteHost: String? = nil
        var remoteIP: String? = nil
        var remotePort: Int? = nil
        var ruleScope: RuleScope = .process

        switch scope {
        case .anyConnection:
            remoteHost = nil
            remoteIP = nil
            remotePort = nil
            ruleScope = .process
        case .thisHost:
            if !c.remoteHost.isEmpty, !NetworkStream.looksLikeIP(c.remoteHost) {
                remoteHost = c.remoteHost
                ruleScope = .domain
            } else {
                remoteIP = c.remoteIP.isEmpty ? nil : c.remoteIP
                ruleScope = .ip
            }
        case .thisIPandPort:
            remoteIP = c.remoteIP.isEmpty ? nil : c.remoteIP
            remotePort = c.remotePort > 0 ? c.remotePort : nil
            ruleScope = .ip
        }

        let sessionNote = duration == .session ? "Until quit" : "Created from alert"
        let rule = Rule(
            processBundleId: c.processBundleId,
            processPath: c.processPath.isEmpty ? nil : c.processPath,
            processName: c.processName,
            codeTeamID: c.codeTeamID,
            requiresSignature: c.signingStatus == .signedValid,
            remoteHost: remoteHost,
            remoteIP: remoteIP,
            remotePort: remotePort,
            direction: c.direction,
            action: allow ? .allow : .deny,
            scope: ruleScope,
            priority: 100,
            profile: activeProfile,
            notes: sessionNote,
            temporary: duration.isTemporary,
            expiresAt: duration.expiresAt
        )
        rules.append(rule)
        helper.addRule(rule)
        try? store?.upsertRule(rule)
        syncSharedRules()
        refreshRules()
    }

    func appendLog(level: String, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        logs.append(entry)
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }

}
