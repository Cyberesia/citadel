import Foundation
import ServiceManagement

/// GUI client for the privileged Citadel helper (frozen XPC selectors).
@MainActor
final class HelperClient: NSObject, ObservableObject {
    @Published var connected = false
    @Published var status: HelperStatus?

    private var connection: NSXPCConnection?
    private var didBootstrap = false
    weak var state: AppState?

    /// Registers the helper via SMAppService (System Settings → Login Items).
    func registerDaemon() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.daemon(plistName: "com.citadel.firewall.helper.plist")
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            let message = "Helper registration failed: \(error.localizedDescription). " +
                "Approve Citadel in System Settings → General → Login Items."
            state?.appendLog(level: "error", message: message)
        }
    }

    func connect() {
        let connection = NSXPCConnection(
            machServiceName: AppConstants.xpcMachServiceName,
            options: [.privileged]
        )
        connection.remoteObjectInterface = HelperBridge.remoteInterface()
        connection.exportedInterface = HelperBridge.exportedInterface()
        connection.exportedObject = HelperEventReceiver(state: state)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.setConnected(false) }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.setConnected(false) }
        }
        connection.resume()
        self.connection = connection
        ping()
        for delay in [2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.ping()
            }
        }
    }

    var remote: HelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { _ in } as? HelperProtocol
    }

    private func setConnected(_ value: Bool) {
        let wasConnected = connected
        connected = value
        state?.helperConnected = value
        guard value, !wasConnected else { return }
        if didBootstrap {
            state?.refreshRules()
        } else {
            didBootstrap = true
            state?.bootstrap()
        }
    }

    func ping() {
        remote?.getVersion { [weak self] version in
            Task { @MainActor in self?.setConnected(!version.isEmpty) }
        }
        remote?.getStatus { [weak self] data in
            let status = try? JSONDecoder().decode(HelperStatus.self, from: data)
            Task { @MainActor in self?.status = status }
        }
    }

    func setMode(_ mode: AppMode) {
        remote?.setMode(rawValue: mode.rawValue) { _, _ in }
    }

    func addRule(_ rule: Rule) {
        guard let data = try? JSONEncoder().encode(rule) else { return }
        remote?.addRule(ruleJSON: data) { _, _ in }
    }

    func removeRule(id: UUID) {
        remote?.removeRule(idString: id.uuidString) { _, _ in }
    }

    func listRules(profile: String = "", completion: @MainActor @escaping ([Rule]) -> Void) {
        remote?.listRules(profile: profile) { data in
            let rules = (try? JSONDecoder().decode([Rule].self, from: data)) ?? []
            Task { @MainActor in completion(rules) }
        }
    }

    func startMonitoring() { remote?.startMonitoring { _, _ in } }
    func refreshBlocklists() { remote?.refreshBlocklists { _, _ in } }
    func installPF() { remote?.installPF { _, _ in } }
    func uninstallPF() { remote?.uninstallPF { _, _ in } }

    func listBlocklists(completion: @MainActor @escaping ([BlocklistInfo]) -> Void) {
        remote?.listBlocklists { data in
            let lists = (try? JSONDecoder().decode([BlocklistInfo].self, from: data)) ?? []
            Task { @MainActor in completion(lists) }
        }
    }

    func listProfiles(completion: @MainActor @escaping ([Profile]) -> Void) {
        remote?.listProfiles { data in
            let profiles = (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
            Task { @MainActor in completion(profiles) }
        }
    }

    func setActiveProfile(_ name: String) {
        remote?.setActiveProfile(name: name) { _, _ in }
    }

    func purgeExpiredRules() {
        remote?.purgeExpiredRules { _, _ in }
    }

    func purgeSessionRules() {
        remote?.purgeSessionRules { _, _ in }
    }

    func installDNS() {
        remote?.setDNSFilterEnabled(enabled: true) { _, _ in }
    }

    func uninstallDNS() {
        remote?.setDNSFilterEnabled(enabled: false) { _, _ in }
    }
}

/// Receives helper push notifications. GUI rates come from Fortress; connections
/// still update denied counts for the menubar.
final class HelperEventReceiver: NSObject, HelperClientProtocol {
    weak var state: AppState?
    init(state: AppState?) { self.state = state }

    func notifyConnection(connectionJSON: Data) {
        guard let connections = try? JSONDecoder().decode([Connection].self, from: connectionJSON) else { return }
        Task { @MainActor in state?.updateConnections(connections) }
    }

    func notifyTraffic(sampleJSON: Data) {
        guard let sample = try? JSONDecoder().decode(TrafficSample.self, from: sampleJSON) else { return }
        Task { @MainActor in state?.appendSample(sample) }
    }

    func notifyAlert(connectionJSON: Data, reply: @escaping (Bool, Bool) -> Void) {
        guard let connection = try? JSONDecoder().decode(Connection.self, from: connectionJSON) else {
            reply(true, false)
            return
        }
        Task { @MainActor in state?.presentAlert(for: connection, reply: reply) }
    }

    func notifyLog(level: String, message: String) {
        Task { @MainActor in state?.appendLog(level: level, message: message) }
    }
}
