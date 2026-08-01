import Foundation
import ServiceManagement

/// GUI-side controller for the privileged Citadel helper daemon.
@MainActor
final class HelperClient: NSObject, ObservableObject {
    @Published var connected = false
    @Published var status: HelperStatus?

    weak var state: AppState? {
        didSet { eventReceiver.state = state }
    }

    private let session = HelperXPCSession()
    private let eventReceiver = HelperEventReceiver(state: nil)
    private var didBootstrap = false

    func registerDaemon() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.daemon(plistName: "com.citadel.firewall.helper.plist")
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            state?.appendLog(
                level: "error",
                message: "Helper registration failed: \(error.localizedDescription). Approve Citadel in System Settings → General → Login Items."
            )
        }
    }

    func connect() {
        session.connect(eventReceiver: eventReceiver) { [weak self] in
            Task { @MainActor in self?.markDisconnected() }
        }
        ping()
        session.scheduleReconnect { [weak self] in self?.ping() }
    }

    private func markDisconnected() {
        connected = false
        state?.helperConnected = false
    }

    private func markConnected() {
        let wasConnected = connected
        connected = true
        state?.helperConnected = true
        guard !wasConnected else { return }
        if didBootstrap {
            state?.refreshRules()
        } else {
            didBootstrap = true
            state?.bootstrap()
        }
    }

    func ping() {
        session.helper?.getVersion { [weak self] version in
            Task { @MainActor in
                if version.isEmpty {
                    self?.markDisconnected()
                } else {
                    self?.markConnected()
                }
            }
        }
        session.helper?.getStatus { [weak self] data in
            let status = try? JSONDecoder().decode(HelperStatus.self, from: data)
            Task { @MainActor in self?.status = status }
        }
    }

    private var helper: HelperProtocol? { session.helper }

    /// Legacy escape hatch for direct HelperProtocol calls.
    var remote: HelperProtocol? { session.helper }

    func setMode(_ mode: AppMode) {
        helper?.setMode(rawValue: mode.rawValue) { _, _ in }
    }

    func addRule(_ rule: Rule) {
        guard let data = try? JSONEncoder().encode(rule) else { return }
        helper?.addRule(ruleJSON: data) { _, _ in }
    }

    func removeRule(id: UUID) {
        helper?.removeRule(idString: id.uuidString) { _, _ in }
    }

    func listRules(profile: String = "", completion: @MainActor @escaping ([Rule]) -> Void) {
        helper?.listRules(profile: profile) { data in
            let rules = (try? JSONDecoder().decode([Rule].self, from: data)) ?? []
            Task { @MainActor in completion(rules) }
        }
    }

    func startMonitoring() { helper?.startMonitoring { _, _ in } }
    func refreshBlocklists() { helper?.refreshBlocklists { _, _ in } }
    func installPF() { helper?.installPF { _, _ in } }
    func uninstallPF() { helper?.uninstallPF { _, _ in } }

    func listBlocklists(completion: @MainActor @escaping ([BlocklistInfo]) -> Void) {
        helper?.listBlocklists { data in
            let lists = (try? JSONDecoder().decode([BlocklistInfo].self, from: data)) ?? []
            Task { @MainActor in completion(lists) }
        }
    }

    func listProfiles(completion: @MainActor @escaping ([Profile]) -> Void) {
        helper?.listProfiles { data in
            let profiles = (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
            Task { @MainActor in completion(profiles) }
        }
    }

    func setActiveProfile(_ name: String) {
        helper?.setActiveProfile(name: name) { _, _ in }
    }

    func purgeExpiredRules() { helper?.purgeExpiredRules { _, _ in } }
    func purgeSessionRules() { helper?.purgeSessionRules { _, _ in } }
    func installDNS() { helper?.setDNSFilterEnabled(enabled: true) { _, _ in } }
    func uninstallDNS() { helper?.setDNSFilterEnabled(enabled: false) { _, _ in } }

    func setDoHUpstream(_ url: String) {
        helper?.setDoHUpstream(url: url) { _, _ in }
    }

    func enableBlocklist(id: UUID, enabled: Bool) {
        helper?.enableBlocklist(idString: id.uuidString, enabled: enabled) { _, _ in }
    }
}
