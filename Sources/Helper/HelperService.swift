import Foundation

/// Privileged helper façade — XPC selectors are a frozen contract (`HelperProtocol`).
final class HelperService: NSObject, HelperProtocol, @unchecked Sendable {
    private let store: RuleStore
    private let packetFilter = PFManager()
    private let dnsProxy = DNSProxy()
    private let netMonitor = NetMonitor()
    private let blocklists: BlocklistManager
    private let listener: NSXPCListener

    private var clientConnections: [NSXPCConnection] = []
    private let clientLock = NSLock()
    private var pendingAsks: [String: (Bool) -> Void] = [:]
    private let askLock = NSLock()
    private var mode: AppMode = .alert

    init(listener: NSXPCListener) throws {
        let dbDir = "/Library/Application Support/Citadel"
        try? FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
        let dbPath = (dbDir as NSString).appendingPathComponent("citadel.sqlite")
        store = try RuleStore(path: dbPath)
        blocklists = BlocklistManager(store: store)
        self.listener = listener
        super.init()

        if let raw = store.getSetting("mode"), let saved = AppMode(rawValue: raw) {
            mode = saved
        }
        dnsProxy.rules = store.allRules()
        dnsProxy.mode = mode
        wireCallbacks()
        listener.delegate = self
    }

    func start() {
        listener.resume()
        netMonitor.start()
        Task { await blocklists.refresh() }
    }

    private func wireCallbacks() {
        dnsProxy.onBlock = { [weak self] domain, _ in
            self?.broadcast { $0.notifyLog(level: "block", message: "blocked: \(domain)") }
        }
        dnsProxy.onResolve = { [weak self] domain, ips in
            SharedDNSNameBridge.record(domain: domain, ips: ips)
            self?.broadcast { $0.notifyLog(level: "resolve", message: "\(domain) -> \(ips.joined(separator: ", "))") }
        }
        dnsProxy.onAsk = { [weak self] domain, completion in
            guard let self else { completion(true); return }
            askLock.lock()
            pendingAsks[domain] = completion
            askLock.unlock()
            let stub = Connection(pid: 0, processName: "dns", processPath: "", remoteHost: domain, status: .pending)
            guard let data = try? JSONEncoder().encode(stub) else { completion(true); return }
            broadcast { client in
                client.notifyAlert(connectionJSON: data) { allow, _ in
                    self.askLock.lock()
                    let callback = self.pendingAsks.removeValue(forKey: domain)
                    self.askLock.unlock()
                    callback?(allow)
                }
            }
        }
        blocklists.onUpdate = { [weak self] _ in
            self?.dnsProxy.blocklist = self?.blocklists.domains ?? []
        }
        netMonitor.onConnections = { [weak self] connections in
            guard let self else { return }
            for connection in connections {
                try? store.recordConnection(connection)
            }
            broadcast { client in
                if let data = try? JSONEncoder().encode(connections) {
                    client.notifyConnection(connectionJSON: data)
                }
            }
        }
        netMonitor.onSample = { [weak self] sample in
            self?.broadcast { client in
                if let data = try? JSONEncoder().encode(sample) {
                    client.notifyTraffic(sampleJSON: data)
                }
            }
        }
    }

    private func registerClient(_ connection: NSXPCConnection) {
        clientLock.lock(); defer { clientLock.unlock() }
        clientConnections.append(connection)
    }

    private func unregisterClient(_ connection: NSXPCConnection) {
        clientLock.lock(); defer { clientLock.unlock() }
        clientConnections.removeAll { $0 === connection }
    }

    private func broadcast(_ body: (HelperClientProtocol) -> Void) {
        clientLock.lock()
        let connections = clientConnections
        clientLock.unlock()
        for connection in connections {
            if let proxy = connection.remoteObjectProxy as? HelperClientProtocol {
                body(proxy)
            }
        }
    }

    private func refreshEnforcement() {
        let rules = store.allRules()
        dnsProxy.rules = rules
        try? packetFilter.applyRules(rules)
    }

    // MARK: - HelperProtocol

    func getVersion(reply: @escaping (String) -> Void) { reply(AppConstants.version) }

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
        guard let next = AppMode(rawValue: rawValue) else { reply(false, "invalid mode"); return }
        mode = next
        dnsProxy.mode = next
        try? store.setSetting("mode", rawValue)
        reply(true, nil)
    }

    func reloadRules(rulesJSON: Data, reply: @escaping (Bool, String?) -> Void) {
        do {
            let rules = try JSONDecoder().decode([Rule].self, from: rulesJSON)
            for rule in rules { try store.upsertRule(rule) }
            refreshEnforcement()
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    func addRule(ruleJSON: Data, reply: @escaping (Bool, String?) -> Void) {
        do {
            let rule = try JSONDecoder().decode(Rule.self, from: ruleJSON)
            try store.upsertRule(rule)
            refreshEnforcement()
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    func removeRule(idString: String, reply: @escaping (Bool, String?) -> Void) {
        guard let id = UUID(uuidString: idString) else { reply(false, "bad uuid"); return }
        do {
            try store.deleteRule(id: id)
            refreshEnforcement()
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    func listRules(profile: String, reply: @escaping (Data) -> Void) {
        let rules = store.allRules(profile: profile.isEmpty ? nil : profile)
        reply((try? JSONEncoder().encode(rules)) ?? Data())
    }

    func startMonitoring(reply: @escaping (Bool, String?) -> Void) {
        netMonitor.start()
        do {
            try dnsProxy.start(port: AppConstants.dnsProxyPort)
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
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
        guard var target = store.allBlocklists().first(where: { $0.id.uuidString == idString }) else {
            reply(false, "blocklist not found"); return
        }
        target.enabled = enabled
        do {
            try store.updateBlocklist(target)
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
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

    func installPF(reply: @escaping (Bool, String?) -> Void) {
        do { try packetFilter.install(); reply(true, nil) } catch { reply(false, "\(error)") }
    }

    func uninstallPF(reply: @escaping (Bool, String?) -> Void) {
        do { try packetFilter.uninstall(); reply(true, nil) } catch { reply(false, "\(error)") }
    }

    func flushAll(reply: @escaping (Bool, String?) -> Void) {
        do { try packetFilter.uninstall(); reply(true, nil) } catch { reply(false, "\(error)") }
    }

    func recentBlocked(limit: Int, reply: @escaping (Data) -> Void) {
        let connections = store.recentConnections(limit: limit, status: .denied)
        reply((try? JSONEncoder().encode(connections)) ?? Data())
    }

    func recentDenied(limit: Int, reply: @escaping (Data) -> Void) {
        recentBlocked(limit: limit, reply: reply)
    }
}

extension HelperService: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = HelperBridge.remoteInterface()
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = HelperBridge.exportedInterface()
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            if let connection = newConnection { self?.unregisterClient(connection) }
        }
        newConnection.interruptionHandler = { [weak self, weak newConnection] in
            if let connection = newConnection { self?.unregisterClient(connection) }
        }
        registerClient(newConnection)
        newConnection.resume()
        return true
    }
}
