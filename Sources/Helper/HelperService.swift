import Foundation

/// Privileged helper daemon — implements the frozen `HelperProtocol` XPC surface.
final class HelperService: NSObject, HelperProtocol, @unchecked Sendable {
    private let store: RuleStore
    private let packetFilter = PFManager()
    private let dnsProxy = DNSProxy()
    private let netMonitor = NetMonitor()
    private let blocklists: BlocklistManager
    private let clients = HelperClientHub()
    private let dnsAsks = PendingDNSAskQueue()
    private let listener: NSXPCListener

    private var mode: AppMode = .alert

    init(listener: NSXPCListener) throws {
        let supportDirectory = "/Library/Application Support/Citadel"
        try? FileManager.default.createDirectory(atPath: supportDirectory, withIntermediateDirectories: true)
        let databasePath = (supportDirectory as NSString).appendingPathComponent("citadel.sqlite")

        store = try RuleStore(path: databasePath)
        blocklists = BlocklistManager(store: store)
        self.listener = listener
        super.init()

        if let savedMode = store.getSetting("mode").flatMap(AppMode.init(rawValue:)) {
            mode = savedMode
        }

        dnsProxy.rules = store.allRules()
        dnsProxy.mode = mode
        bindSubsystems()
        listener.delegate = self
    }

    func start() {
        listener.resume()
        netMonitor.start()
        Task { await blocklists.refresh() }
    }

    // MARK: - Subsystem wiring

    private func bindSubsystems() {
        bindDNSProxy()
        bindBlocklists()
        bindNetMonitor()
    }

    private func bindDNSProxy() {
        dnsProxy.onBlock = { [weak self] domain, _ in
            self?.clients.broadcast {
                $0.notifyLog(level: "block", message: "blocked: \(domain)")
            }
        }

        dnsProxy.onResolve = { [weak self] domain, addresses in
            SharedDNSNameBridge.record(domain: domain, ips: addresses)
            self?.clients.broadcast {
                $0.notifyLog(level: "resolve", message: "\(domain) -> \(addresses.joined(separator: ", "))")
            }
        }

        dnsProxy.onAsk = { [weak self] domain, completion in
            guard let self else {
                completion(true)
                return
            }
            dnsAsks.enqueue(domain: domain, callback: completion)
            promptForDNS(domain: domain)
        }
    }

    private func promptForDNS(domain: String) {
        let stub = Connection(
            pid: 0,
            processName: "dns",
            processPath: "",
            remoteHost: domain,
            status: .pending
        )
        guard let payload = try? JSONEncoder().encode(stub) else {
            dnsAsks.complete(domain: domain, allowed: true)
            return
        }

        clients.broadcast { [weak self] client in
            client.notifyAlert(connectionJSON: payload) { allow, _ in
                self?.dnsAsks.complete(domain: domain, allowed: allow)
            }
        }
    }

    private func bindBlocklists() {
        blocklists.onUpdate = { [weak self] _ in
            guard let self else { return }
            dnsProxy.blocklist = blocklists.domains
        }
    }

    private func bindNetMonitor() {
        netMonitor.onConnections = { [weak self] connections in
            guard let self else { return }
            for connection in connections {
                try? store.recordConnection(connection)
            }
            guard let payload = try? JSONEncoder().encode(connections) else { return }
            clients.broadcast { $0.notifyConnection(connectionJSON: payload) }
        }

        netMonitor.onSample = { [weak self] sample in
            guard let payload = try? JSONEncoder().encode(sample) else { return }
            self?.clients.broadcast { $0.notifyTraffic(sampleJSON: payload) }
        }
    }

    private func syncEnforcement() {
        let rules = store.allRules()
        dnsProxy.rules = rules
        try? packetFilter.applyRules(rules)
    }

    // MARK: - HelperProtocol

    func getVersion(reply: @escaping (String) -> Void) {
        reply(AppConstants.version)
    }

    func getStatus(reply: @escaping (Data) -> Void) {
        let status = HelperStatus(
            version: AppConstants.version,
            running: true,
            pfctlActive: packetFilter.isLoaded,
            dnsProxyActive: dnsProxy.running,
            dnsProxyPort: Int(dnsProxy.port),
            activeRules: store.allRules().count,
            blockedToday: dnsProxy.statistics.blocked
        )
        reply((try? JSONEncoder().encode(status)) ?? Data())
    }

    func setMode(rawValue: String, reply: @escaping (Bool, String?) -> Void) {
        guard let nextMode = AppMode(rawValue: rawValue) else {
            reply(false, "invalid mode")
            return
        }
        mode = nextMode
        dnsProxy.mode = nextMode
        try? store.setSetting("mode", rawValue)
        reply(true, nil)
    }

    func reloadRules(rulesJSON: Data, reply: @escaping (Bool, String?) -> Void) {
        do {
            let rules = try JSONDecoder().decode([Rule].self, from: rulesJSON)
            for rule in rules { try store.upsertRule(rule) }
            syncEnforcement()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func addRule(ruleJSON: Data, reply: @escaping (Bool, String?) -> Void) {
        do {
            let rule = try JSONDecoder().decode(Rule.self, from: ruleJSON)
            try store.upsertRule(rule)
            syncEnforcement()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func removeRule(idString: String, reply: @escaping (Bool, String?) -> Void) {
        guard let id = UUID(uuidString: idString) else {
            reply(false, "bad uuid")
            return
        }
        do {
            try store.deleteRule(id: id)
            syncEnforcement()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func listRules(profile: String, reply: @escaping (Data) -> Void) {
        let profileName = profile.isEmpty ? nil : profile
        let rules = store.allRules(profile: profileName)
        reply((try? JSONEncoder().encode(rules)) ?? Data())
    }

    func startMonitoring(reply: @escaping (Bool, String?) -> Void) {
        netMonitor.start()
        do {
            try dnsProxy.start(port: AppConstants.dnsProxyPort)
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func stopMonitoring(reply: @escaping (Bool, String?) -> Void) {
        dnsProxy.stop()
        netMonitor.stop()
        reply(true, nil)
    }

    func currentConnections(reply: @escaping (Data) -> Void) {
        let connections = store.recentConnections(limit: 500)
        reply((try? JSONEncoder().encode(connections)) ?? Data())
    }

    func currentTrafficSample(reply: @escaping (Data) -> Void) {
        let sample = TrafficSample(timestamp: Date(), bytesIn: 0, bytesOut: 0)
        reply((try? JSONEncoder().encode(sample)) ?? Data())
    }

    func enableBlocklist(idString: String, enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        guard var blocklist = store.allBlocklists().first(where: { $0.id.uuidString == idString }) else {
            reply(false, "blocklist not found")
            return
        }
        blocklist.enabled = enabled
        do {
            try store.updateBlocklist(blocklist)
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
            return
        }
        Task { await blocklists.refresh() }
    }

    func refreshBlocklists(reply: @escaping (Bool, String?) -> Void) {
        Task {
            await blocklists.refresh()
            reply(true, nil)
        }
    }

    func setDoHUpstream(url: String, reply: @escaping (Bool, String?) -> Void) {
        dnsProxy.dohURL = url
        try? store.setSetting("doh_url", url)
        reply(true, nil)
    }

    func listBlocklists(reply: @escaping (Data) -> Void) {
        reply((try? JSONEncoder().encode(store.allBlocklists())) ?? Data())
    }

    func listProfiles(reply: @escaping (Data) -> Void) {
        reply((try? JSONEncoder().encode(store.allProfiles())) ?? Data())
    }

    func setActiveProfile(name: String, reply: @escaping (Bool, String?) -> Void) {
        do {
            try store.setActiveProfile(name: name)
            if let profile = store.allProfiles().first(where: { $0.name == name }) {
                mode = profile.mode
                dnsProxy.mode = profile.mode
                try? store.setSetting("mode", profile.mode.rawValue)
            }
            syncEnforcement()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func purgeExpiredRules(reply: @escaping (Bool, String?) -> Void) {
        do {
            try store.purgeExpiredRules()
            syncEnforcement()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func purgeSessionRules(reply: @escaping (Bool, String?) -> Void) {
        do {
            try store.purgeSessionRules()
            syncEnforcement()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func setDNSFilterEnabled(enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        do {
            try store.setSetting("dns_filter_enabled", enabled ? "1" : "0")
            if enabled {
                try dnsProxy.start(port: AppConstants.dnsProxyPort)
            } else {
                dnsProxy.stop()
            }
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func installPF(reply: @escaping (Bool, String?) -> Void) {
        do {
            try packetFilter.install()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func uninstallPF(reply: @escaping (Bool, String?) -> Void) {
        do {
            try packetFilter.uninstall()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func flushAll(reply: @escaping (Bool, String?) -> Void) {
        do {
            try packetFilter.uninstall()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func recentBlocked(limit: Int, reply: @escaping (Data) -> Void) {
        let connections = store.recentConnections(limit: limit, status: .denied)
        reply((try? JSONEncoder().encode(connections)) ?? Data())
    }

    func recentDenied(limit: Int, reply: @escaping (Data) -> Void) {
        recentBlocked(limit: limit, reply: reply)
    }
}

// MARK: - NSXPCListenerDelegate

extension HelperService: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = HelperBridge.remoteInterface()
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = HelperBridge.exportedInterface()

        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let connection = newConnection else { return }
            self?.clients.detach(connection)
        }
        newConnection.interruptionHandler = { [weak self, weak newConnection] in
            guard let connection = newConnection else { return }
            self?.clients.detach(connection)
        }

        clients.attach(newConnection)
        newConnection.resume()
        return true
    }
}
