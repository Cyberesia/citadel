import Foundation

/// Converts cumulative byte counters into per-second rates.
public struct RateCalculator: Sendable {
    private var lastIn: Int64 = 0
    private var lastOut: Int64 = 0
    private var lastTime: Date = .distantPast
    private var primed = false

    public init() {}

    public mutating func rate(totalIn: Int64, totalOut: Int64, now: Date = Date()) -> BandwidthRate? {
        defer {
            lastIn = totalIn
            lastOut = totalOut
            lastTime = now
            primed = true
        }
        guard primed else { return nil }
        let dt = now.timeIntervalSince(lastTime)
        guard dt >= 0.3 else { return nil }
        let deltaIn = max(0, totalIn - lastIn)
        let deltaOut = max(0, totalOut - lastOut)
        return BandwidthRate(
            bytesIn: Int64(Double(deltaIn) / max(dt, 1)),
            bytesOut: Int64(Double(deltaOut) / max(dt, 1)),
            timestamp: now
        )
    }
}

/// Per-PID rate tracking from cumulative nettop counters.
public struct ProcessRateTracker: Sendable {
    private var last: [pid_t: (in: Int64, out: Int64)] = [:]
    private var lastTime: Date = .distantPast
    private var primed = false

    public init() {}

    public mutating func rates(
        cumulative: [pid_t: (name: String, in: Int64, out: Int64)],
        now: Date = Date()
    ) -> [ProcessBandwidth] {
        defer {
            last = cumulative.mapValues { ($0.in, $0.out) }
            lastTime = now
            primed = true
        }
        guard primed else { return [] }
        let dt = now.timeIntervalSince(lastTime)
        guard dt >= 0.3 else { return [] }

        var samples: [ProcessBandwidth] = []
        for (pid, entry) in cumulative {
            let previous = last[pid] ?? (0, 0)
            let deltaIn = max(0, entry.in - previous.in)
            let deltaOut = max(0, entry.out - previous.out)
            let rateIn = Int64(Double(deltaIn) / max(dt, 1))
            let rateOut = Int64(Double(deltaOut) / max(dt, 1))
            if rateIn > 0 || rateOut > 0 {
                samples.append(ProcessBandwidth(
                    pid: pid,
                    processName: entry.name,
                    rateIn: rateIn,
                    rateOut: rateOut
                ))
            }
        }
        return samples
    }
}

/// Streams machine + per-process throughput via a single `nettop` process.
public final class ThroughputSampler: @unchecked Sendable {
    private var nettopProc: Process?
    private let queue = DispatchQueue(label: "com.citadel.fortress.throughput", qos: .utility)
    private var machineCalc = RateCalculator()
    private var processTracker = ProcessRateTracker()

    public var onMachineRate: ((BandwidthRate) -> Void)?
    public var onProcessRates: (([ProcessBandwidth]) -> Void)?

    public init() {}

    public func start() {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-x", "-L", "0", "-J", "bytes_in,bytes_out", "-s", "1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return }
        nettopProc = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            self.queue.async { self.parse(text) }
        }
    }

    public func stop() {
        nettopProc?.terminate()
        nettopProc = nil
        machineCalc = RateCalculator()
        processTracker = ProcessRateTracker()
    }

    private func parse(_ chunk: String) {
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0
        var cumulative: [pid_t: (name: String, in: Int64, out: Int64)] = [:]

        for line in chunk.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("bytes_") { continue }
            let parts = trimmed.split(separator: ",").map(String.init)
            guard parts.count >= 3 else { continue }
            guard let bytesIn = Int64(parts[parts.count - 2]),
                  let bytesOut = Int64(parts[parts.count - 1]) else { continue }

            let (name, pid) = parseProcessField(parts[0])
            guard pid > 0 else { continue }
            cumulative[pid] = (name, bytesIn, bytesOut)
            totalIn += bytesIn
            totalOut += bytesOut
        }

        let now = Date()
        if let machine = machineCalc.rate(totalIn: totalIn, totalOut: totalOut, now: now) {
            onMachineRate?(machine)
        }
        let processes = processTracker.rates(cumulative: cumulative, now: now)
        if !processes.isEmpty {
            onProcessRates?(processes)
        }
    }

    private func parseProcessField(_ field: String) -> (String, pid_t) {
        guard let dot = field.lastIndex(of: ".") else { return (field, 0) }
        let name = String(field[..<dot])
        let pidStr = String(field[field.index(after: dot)...])
        return (name, pid_t(pidStr) ?? 0)
    }
}
