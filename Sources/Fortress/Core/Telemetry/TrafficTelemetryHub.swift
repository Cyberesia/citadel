import Foundation

public enum TelemetryEvent: Sendable {
    case streamsChanged(added: Int, updated: Int, removed: Int)
    case machineRate(BandwidthRate)
    case processRates([ProcessBandwidth])
}

/// Coordinates socket inventory + throughput sampling into a FlowIndex.
public final class TrafficTelemetryHub: @unchecked Sendable {
    private let sockets = SocketInventorySource()
    private let throughput = ThroughputSampler()
    private let resolver = ProcessIdentityResolver()
    public let index = FlowIndex()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.citadel.fortress.hub", qos: .utility)
    private var eventContinuation: AsyncStream<TelemetryEvent>.Continuation?
    private var running = false
    private var activeStreamCount = 0

    public private(set) lazy var events: AsyncStream<TelemetryEvent> = {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }()

    public init() {}

    public func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.resolver.clearCache()
            self.index.reset()
            self.startTimer(interval: 1.5)
            self.throughput.onMachineRate = { [weak self] rate in
                self?.index.applyMachineRate(rate)
                self?.emit(.machineRate(rate))
            }
            self.throughput.onProcessRates = { [weak self] rates in
                self?.index.applyProcessRates(rates)
                self?.emit(.processRates(rates))
            }
            self.throughput.start()
            self.pollSockets()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.timer?.cancel()
            self.timer = nil
            self.throughput.stop()
            self.throughput.onMachineRate = nil
            self.throughput.onProcessRates = nil
        }
    }

    public func applyGeo(_ map: [String: FortressGeoLocation]) {
        index.applyGeo(map)
        emit(.streamsChanged(added: 0, updated: map.count, removed: 0))
    }

    public func applyRemoteHosts(_ map: [String: String]) {
        index.applyRemoteHosts(map)
        emit(.streamsChanged(added: 0, updated: map.count, removed: 0))
    }

    private func startTimer(interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.pollSockets() }
        t.resume()
        timer = t
    }

    private func pollSockets() {
        guard running else { return }
        let endpoints = sockets.snapshot()
        let pairs = endpoints.map { ($0.pid, $0.processName) }
        // Unique PIDs
        var seen = Set<pid_t>()
        var unique: [(pid_t, String)] = []
        for p in pairs where seen.insert(p.0).inserted {
            unique.append(p)
        }
        let identities = resolver.resolveBatch(pids: unique)
        let delta = index.upsert(endpoints: endpoints, identities: identities)
        activeStreamCount = index.allStreams.count

        // Adaptive interval
        let nextInterval: TimeInterval = activeStreamCount > 0 ? 1.2 : 4.0
        startTimer(interval: nextInterval)

        if delta.added.count + delta.updated.count + delta.removed.count > 0 {
            emit(.streamsChanged(
                added: delta.added.count,
                updated: delta.updated.count,
                removed: delta.removed.count
            ))
        }
    }

    private func emit(_ event: TelemetryEvent) {
        eventContinuation?.yield(event)
    }
}
