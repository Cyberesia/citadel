import Foundation

/// Fixed-size ring buffer for sparklines / recent rate history.
public struct MetricRingBuffer: Sendable {
    private var samples: [Int64]
    private var index = 0
    private var count = 0
    public let capacity: Int

    public init(capacity: Int = 60) {
        self.capacity = max(2, capacity)
        self.samples = Array(repeating: 0, count: self.capacity)
    }

    public mutating func push(_ value: Int64) {
        samples[index] = value
        index = (index + 1) % capacity
        count = min(count + 1, capacity)
    }

    public func sparkline(points: Int? = nil) -> [Int64] {
        let n = min(points ?? count, count)
        guard n > 0 else { return [] }
        var result: [Int64] = []
        result.reserveCapacity(n)
        let start = (index - count + capacity) % capacity
        for i in 0..<n {
            let idx = (start + (count - n) + i) % capacity
            result.append(samples[idx])
        }
        return result
    }

    public var latest: Int64 {
        guard count > 0 else { return 0 }
        let idx = (index - 1 + capacity) % capacity
        return samples[idx]
    }
}

/// Maintains the live stream table and emits deltas for the UI.
public final class FlowIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [String: NetworkStream] = [:]
    private var processRates: [pid_t: (in: Int64, out: Int64)] = [:]
    private var familySparklines: [String: MetricRingBuffer] = [:]
    private var streamSparklines: [String: MetricRingBuffer] = [:]
    private var machineSparkline = MetricRingBuffer(capacity: 60)

    public init() {}

    public var allStreams: [NetworkStream] {
        lock.lock(); defer { lock.unlock() }
        return Array(streams.values)
    }

    public func stream(id: String) -> NetworkStream? {
        lock.lock(); defer { lock.unlock() }
        return streams[id]
    }

    public func upsert(
        endpoints: [SocketEndpoint],
        identities: [pid_t: ProcessIdentity],
        now: Date = Date()
    ) -> (added: [NetworkStream], updated: [NetworkStream], removed: [String]) {
        lock.lock(); defer { lock.unlock() }

        var seen = Set<String>()
        var added: [NetworkStream] = []
        var updated: [NetworkStream] = []

        for ep in endpoints {
            let identity = identities[ep.pid] ?? ProcessIdentity(
                pid: ep.pid,
                name: ep.processName,
                familyID: ep.processName.lowercased(),
                familyName: ep.processName
            )
            let id = NetworkStream.makeID(
                pid: ep.pid,
                remoteIP: ep.remoteHost,
                remotePort: ep.remotePort,
                proto: ep.protocolName
            )
            seen.insert(id)
            let rates = processRates[ep.pid] ?? (0, 0)

            if var existing = streams[id] {
                existing.process = identity
                existing.lastSeen = now
                existing.rateIn = rates.in
                existing.rateOut = rates.out
                streams[id] = existing
                updated.append(existing)
            } else {
                let stream = NetworkStream(
                    id: id,
                    process: identity,
                    remoteHost: ep.remoteHost,
                    remoteIP: ep.remoteHost,
                    remotePort: ep.remotePort,
                    protocolName: ep.protocolName,
                    rateIn: rates.in,
                    rateOut: rates.out,
                    status: .established,
                    firstSeen: now,
                    lastSeen: now
                )
                streams[id] = stream
                added.append(stream)
            }
        }

        var removed: [String] = []
        for id in streams.keys where !seen.contains(id) {
            // Keep briefly so UI doesn't flicker; remove if stale > 8s
            if let s = streams[id], now.timeIntervalSince(s.lastSeen) > 8 {
                streams.removeValue(forKey: id)
                streamSparklines.removeValue(forKey: id)
                removed.append(id)
            }
        }
        return (added, updated, removed)
    }

    public func applyProcessRates(_ rates: [ProcessBandwidth]) {
        lock.lock(); defer { lock.unlock() }
        for r in rates {
            processRates[r.pid] = (r.rateIn, r.rateOut)
        }
        // Push sparklines for families that have matching streams
        var familyRates: [String: Int64] = [:]
        for stream in streams.values {
            let rates = processRates[stream.process.pid] ?? (0, 0)
            var s = stream
            s.rateIn = rates.in
            s.rateOut = rates.out
            streams[stream.id] = s
            familyRates[stream.process.familyID, default: 0] += rates.in + rates.out
            var spark = streamSparklines[stream.id] ?? MetricRingBuffer(capacity: 60)
            spark.push(rates.in + rates.out)
            streamSparklines[stream.id] = spark
        }
        for (familyID, total) in familyRates {
            var spark = familySparklines[familyID] ?? MetricRingBuffer(capacity: 60)
            spark.push(total)
            familySparklines[familyID] = spark
        }
    }

    public func applyMachineRate(_ rate: BandwidthRate) {
        lock.lock(); defer { lock.unlock() }
        machineSparkline.push(rate.bytesIn + rate.bytesOut)
    }

    public func applyGeo(_ map: [String: SentinelGeoLocation]) {
        lock.lock(); defer { lock.unlock() }
        for (ip, geo) in map {
            for (id, var stream) in streams where stream.remoteIP == ip {
                stream.geo = geo
                if let reverse = geo.reverseHost, !reverse.isEmpty,
                   stream.remoteHost.isEmpty || stream.remoteHost == stream.remoteIP
                    || NetworkStream.looksLikeIP(stream.remoteHost) {
                    stream.remoteHost = reverse
                }
                streams[id] = stream
            }
        }
    }

    /// Apply reverse-DNS hostnames (IP → hostname) without clobbering existing names.
    public func applyRemoteHosts(_ map: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        for (ip, host) in map {
            guard !host.isEmpty else { continue }
            for (id, var stream) in streams where stream.remoteIP == ip {
                if stream.remoteHost.isEmpty || stream.remoteHost == stream.remoteIP
                    || NetworkStream.looksLikeIP(stream.remoteHost) {
                    stream.remoteHost = host
                    streams[id] = stream
                }
            }
        }
    }

    public func sparkline(forFamily familyID: String) -> [Int64] {
        lock.lock(); defer { lock.unlock() }
        return familySparklines[familyID]?.sparkline() ?? []
    }

    public func sparkline(forStream streamID: String) -> [Int64] {
        lock.lock(); defer { lock.unlock() }
        return streamSparklines[streamID]?.sparkline() ?? []
    }

    public func machineSparklineValues() -> [Int64] {
        lock.lock(); defer { lock.unlock() }
        return machineSparkline.sparkline()
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        streams.removeAll()
        processRates.removeAll()
        familySparklines.removeAll()
        streamSparklines.removeAll()
        machineSparkline = MetricRingBuffer(capacity: 60)
    }
}
