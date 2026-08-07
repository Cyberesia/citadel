import Foundation
import Network

/// Local DNS resolver that applies Citadel rules and forwards allowed queries via DoH.
final class DNSProxy: @unchecked Sendable {
    private let workQueue = DispatchQueue(label: "com.citadel.firewall.dns", qos: .userInitiated)
    private var udpListener: NWListener?
    private var tcpListener: NWListener?
    private let dohClient = DoHClient()
    private let counters = DNSProxyCounters()

    private(set) var port: UInt16 = 53
    private(set) var running = false

    var blocklist: Set<String> = []
    var rules: [Rule] = []
    var mode: AppMode = .alert
    var evaluator = FirewallRuleEvaluator()
    var dohURL: String = AppConstants.defaultDoHUpstream

    var onBlock: ((String, String?) -> Void)?
    var onResolve: ((String, [String]) -> Void)?
    var onAsk: ((String, @escaping (Bool) -> Void) -> Void)?

    var statistics: (queries: Int, blocked: Int, allowed: Int) {
        counters.snapshot()
    }

    func start(port: UInt16 = 53) throws {
        guard !running else { return }
        try bind(port: port)
        running = true
        CitadelLog.info(CitadelLog.dns, "DNS proxy listening on \(port) (UDP+TCP)")
    }

    func stop() {
        udpListener?.cancel()
        tcpListener?.cancel()
        udpListener = nil
        tcpListener = nil
        running = false
    }

    // MARK: - Binding

    private func bind(port: UInt16) throws {
        self.port = port
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw DNSProxyError.invalidPort(port)
        }

        let udpParameters = NWParameters.udp
        udpParameters.allowLocalEndpointReuse = true
        let udp = try NWListener(using: udpParameters, on: endpointPort)
        udp.newConnectionHandler = { [weak self] connection in
            self?.serveUDP(connection)
        }
        udp.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                CitadelLog.error(CitadelLog.dns, "UDP listener failed: \(error)")
                self?.running = false
            }
        }
        udp.start(queue: workQueue)
        udpListener = udp

        let tcpParameters = NWParameters.tcp
        tcpParameters.allowLocalEndpointReuse = true
        let tcp = try NWListener(using: tcpParameters, on: endpointPort)
        tcp.newConnectionHandler = { [weak self] connection in
            self?.serveTCP(connection)
        }
        tcp.start(queue: workQueue)
        tcpListener = tcp
    }

    // MARK: - UDP

    private func serveUDP(_ connection: NWConnection) {
        connection.start(queue: workQueue)
        connection.receiveMessage { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let self, let data, !data.isEmpty else { return }

            self.handleQuery(wireData: data) { response in
                guard let response else { return }
                connection.send(content: response, completion: .contentProcessed { _ in })
            }
        }
    }

    // MARK: - TCP (RFC 7766 length-prefix framing)

    private func serveTCP(_ connection: NWConnection) {
        connection.start(queue: workQueue)
        readTCPMessages(from: connection, buffer: Data())
    }

    private func readTCPMessages(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_535) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                connection.cancel()
                return
            }

            var pending = buffer + data
            while pending.count >= 2 {
                let messageLength = (Int(pending[0]) << 8) | Int(pending[1])
                guard pending.count >= 2 + messageLength else { break }

                let payload = pending.subdata(in: 2..<(2 + messageLength))
                pending.removeSubrange(0..<(2 + messageLength))

                self.handleQuery(wireData: payload) { response in
                    guard let response else { return }
                    var framed = Data([UInt8((response.count >> 8) & 0xFF), UInt8(response.count & 0xFF)])
                    framed.append(response)
                    connection.send(content: framed, completion: .contentProcessed { _ in })
                }
            }

            self.readTCPMessages(from: connection, buffer: pending)
        }
    }

    // MARK: - Query pipeline

    private func handleQuery(wireData: Data, completion: @escaping (Data?) -> Void) {
        counters.recordQuery()

        guard let question = DNSMessageCodec.firstQuestion(in: wireData) else {
            completion(nil)
            return
        }

        let domain = question.name.lowercased()
        let policy = lookupPolicy(for: domain)

        switch policy {
        case .deny(let reason):
            counters.recordBlocked()
            onBlock?(domain, reason)
            completion(DNSMessageCodec.nxDomainResponse(for: wireData))
        case .ask:
            onAsk?(domain) { [weak self] allowed in
                guard let self else {
                    completion(nil)
                    return
                }
                if allowed {
                    self.forwardUpstream(query: wireData, domain: domain, completion: completion)
                } else {
                    self.counters.recordBlocked()
                    self.onBlock?(domain, "ask-denied")
                    completion(DNSMessageCodec.nxDomainResponse(for: wireData))
                }
            }
        case .allow:
            forwardUpstream(query: wireData, domain: domain, completion: completion)
        }
    }

    private enum PolicyOutcome {
        case allow
        case deny(reason: String?)
        case ask
    }

    private func lookupPolicy(for domain: String) -> PolicyOutcome {
        if DomainBlocklistMatcher(domains: blocklist).matches(domain) {
            return .deny(reason: "blocklist")
        }

        let stub = Connection(
            pid: 0,
            processName: "",
            processPath: "",
            remoteHost: domain,
            direction: .outgoing,
            status: .pending
        )

        switch evaluator.decision(for: stub, rules: rules, defaultMode: mode) {
        case .allow: return .allow
        case .deny: return .deny(reason: nil)
        case .ask: return .ask
        }
    }

    private func forwardUpstream(query: Data, domain: String, completion: @escaping (Data?) -> Void) {
        counters.recordAllowed()
        dohClient.resolve(query: query, upstream: dohURL) { [weak self] result in
            switch result {
            case .success(let response):
                if let answers = DNSMessageCodec.answerStrings(in: response) {
                    self?.onResolve?(domain, answers)
                }
                completion(response)
            case .failure:
                completion(nil)
            }
        }
    }
}

// MARK: - Supporting types

private enum DNSProxyError: LocalizedError {
    case invalidPort(UInt16)

    var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid DNS proxy port: \(port)"
        }
    }
}

private struct DomainBlocklistMatcher {
    let domains: Set<String>

    func matches(_ domain: String) -> Bool {
        let normalized = domain.lowercased()
        if domains.contains(normalized) { return true }

        var suffix = normalized
        while let dot = suffix.firstIndex(of: ".") {
            suffix = String(suffix[suffix.index(after: dot)...])
            if domains.contains(suffix) { return true }
        }
        return false
    }
}

private final class DoHClient: @unchecked Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        session = URLSession(configuration: config)
    }

    func resolve(
        query: Data,
        upstream: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let url = URL(string: upstream) else {
            completion(.failure(DoHClientError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = query

        session.dataTask(with: request) { data, _, error in
            if let error {
                CitadelLog.error(CitadelLog.dns, "DoH upstream failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let data, !data.isEmpty else {
                completion(.failure(DoHClientError.emptyResponse))
                return
            }
            completion(.success(data))
        }.resume()
    }
}

private enum DoHClientError: Error {
    case invalidURL
    case emptyResponse
}

private final class DNSProxyCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var queries = 0
    private var blocked = 0
    private var allowed = 0

    func recordQuery() {
        lock.lock(); queries += 1; lock.unlock()
    }

    func recordBlocked() {
        lock.lock(); blocked += 1; lock.unlock()
    }

    func recordAllowed() {
        lock.lock(); allowed += 1; lock.unlock()
    }

    func snapshot() -> (queries: Int, blocked: Int, allowed: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (queries, blocked, allowed)
    }
}
