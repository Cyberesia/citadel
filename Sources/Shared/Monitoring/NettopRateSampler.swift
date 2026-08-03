import Foundation

public struct ProcessTrafficSample: Sendable {
    public let pid: Int32
    public let processName: String
    public let bytesInRate: Int64
    public let bytesOutRate: Int64
}

/// Converts streaming `nettop` CSV output into byte-rate samples.
final class NettopRateSampler: @unchecked Sendable {
    var onAggregateSample: ((TrafficSample) -> Void)?
    var onProcessSamples: (([ProcessTrafficSample]) -> Void)?

    private let minimumInterval: TimeInterval = 0.4
    private var aggregateBaseline: (bytesIn: Int64, bytesOut: Int64, timestamp: Date)?
    private var processBaseline: [Int32: (name: String, bytesIn: Int64, bytesOut: Int64)] = [:]
    private var processBaselineTimestamp = Date()

    func ingest(chunk: String) {
        let rows = parseRows(chunk)
        guard !rows.isEmpty else { return }

        let now = Date()
        emitAggregateSample(from: rows, at: now)
        emitProcessSamples(from: rows, at: now)
    }

    // MARK: - Parsing

    private struct Row {
        let processName: String
        let pid: Int32
        let bytesIn: Int64
        let bytesOut: Int64
    }

    private func parseRows(_ chunk: String) -> [Row] {
        var rows: [Row] = []
        for rawLine in chunk.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("bytes_") { continue }

            let fields = line.split(separator: ",").map(String.init)
            guard fields.count >= 3,
                  let bytesIn = Int64(fields[fields.count - 2]),
                  let bytesOut = Int64(fields[fields.count - 1]) else {
                continue
            }

            let (name, pid) = splitProcessField(fields[0])
            guard pid > 0 else { continue }
            rows.append(Row(processName: name, pid: pid, bytesIn: bytesIn, bytesOut: bytesOut))
        }
        return rows
    }

    private func splitProcessField(_ field: String) -> (String, Int32) {
        guard let dot = field.lastIndex(of: ".") else { return (field, 0) }
        let name = String(field[..<dot])
        let pid = Int32(field[field.index(after: dot)...]) ?? 0
        return (name, pid)
    }

    // MARK: - Aggregate throughput

    private func emitAggregateSample(from rows: [Row], at timestamp: Date) {
        let totalIn = rows.reduce(Int64(0)) { $0 + $1.bytesIn }
        let totalOut = rows.reduce(Int64(0)) { $0 + $1.bytesOut }

        guard let baseline = aggregateBaseline else {
            aggregateBaseline = (totalIn, totalOut, timestamp)
            return
        }

        let elapsed = timestamp.timeIntervalSince(baseline.timestamp)
        guard elapsed >= minimumInterval else { return }

        let sample = TrafficSample(
            timestamp: timestamp,
            bytesIn: rate(delta: max(0, totalIn - baseline.bytesIn), over: elapsed),
            bytesOut: rate(delta: max(0, totalOut - baseline.bytesOut), over: elapsed)
        )
        aggregateBaseline = (totalIn, totalOut, timestamp)
        onAggregateSample?(sample)
    }

    // MARK: - Per-process throughput

    private func emitProcessSamples(from rows: [Row], at timestamp: Date) {
        var cumulative: [Int32: (name: String, bytesIn: Int64, bytesOut: Int64)] = [:]
        for row in rows {
            cumulative[row.pid] = (row.processName, row.bytesIn, row.bytesOut)
        }

        if processBaseline.isEmpty {
            processBaseline = cumulative
            processBaselineTimestamp = timestamp
            return
        }

        let elapsed = timestamp.timeIntervalSince(processBaselineTimestamp)
        guard elapsed >= minimumInterval else { return }

        var samples: [ProcessTrafficSample] = []
        for (pid, current) in cumulative {
            let previous = processBaseline[pid] ?? (current.name, 0, 0)
            let rateIn = rate(delta: max(0, current.bytesIn - previous.bytesIn), over: elapsed)
            let rateOut = rate(delta: max(0, current.bytesOut - previous.bytesOut), over: elapsed)
            if rateIn > 0 || rateOut > 0 {
                samples.append(ProcessTrafficSample(
                    pid: pid,
                    processName: current.name,
                    bytesInRate: rateIn,
                    bytesOutRate: rateOut
                ))
            }
        }

        processBaseline = cumulative
        processBaselineTimestamp = timestamp
        if !samples.isEmpty {
            onProcessSamples?(samples)
        }
    }

    private func rate(delta: Int64, over interval: TimeInterval) -> Int64 {
        Int64(Double(delta) / max(interval, 1))
    }
}
