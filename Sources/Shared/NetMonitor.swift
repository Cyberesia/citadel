import Foundation

public struct ProcessTrafficSample: Sendable {
    public let pid: Int32
    public let processName: String
    public let bytesInRate: Int64
    public let bytesOutRate: Int64
}

final class NetMonitor: @unchecked Sendable {
    private var lsofTimer: DispatchSourceTimer?
    private var nettopProc: Process?
    private let queue = DispatchQueue(label: "com.citadel.firewall.netmon", qos: .utility)

    var onConnections: (([Connection]) -> Void)?
    var onSample: ((TrafficSample) -> Void)?
    var onProcessTraffic: (([ProcessTrafficSample]) -> Void)?

    private var lastIn: Int64 = 0
    private var lastOut: Int64 = 0
    private var lastSampleTime = Date()
    private var lastProcessBytes: [Int32: (in: Int64, out: Int64)] = [:]
    private var lastProcessSampleTime = Date()

    func start() {
        stop()   // idempotent: tear down any existing pollers before (re)starting
        startLsofPolling()
        startNettop()
    }

    func stop() {
        lsofTimer?.cancel(); lsofTimer = nil
        nettopProc?.terminate(); nettopProc = nil
    }

    private func startLsofPolling() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: .seconds(2))
        t.setEventHandler { [weak self] in self?.pollLsof() }
        t.resume()
        lsofTimer = t
    }

    private func pollLsof() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-i", "-n", "-P", "-F", "pcnT"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let txt = String(data: data, encoding: .utf8) else { return }

        var conns: [Connection] = []
        var pid: Int32 = 0
        var pname = ""
        for line in txt.split(separator: "\n") {
            guard let first = line.first else { continue }
            let rest = String(line.dropFirst())
            switch first {
            case "p":
                pid = Int32(rest) ?? 0
            case "c":
                pname = rest
            case "n":
                if let c = parseN(line: rest, pid: pid, name: pname) { conns.append(c) }
            default: break
            }
        }
        onConnections?(conns)
    }

    private func parseN(line: String, pid: Int32, name: String) -> Connection? {
        guard line.contains("->") else { return nil }
        let parts = line.split(separator: " ").map(String.init)
        let addrPart = parts.first ?? line
        let halves = addrPart.split(separator: "-", maxSplits: 1).map(String.init)
        guard halves.count == 2 else { return nil }
        let local = halves[0]
        let remoteRaw = halves[1].hasPrefix(">") ? String(halves[1].dropFirst()) : halves[1]
        guard let (lip, lport) = splitHostPort(local) else { return nil }
        guard let (rip, rport) = splitHostPort(remoteRaw) else { return nil }
        _ = lip
        let path = pidPath(pid)
        let bundle = bundleID(forPath: path)
        return Connection(
            pid: pid,
            processName: name,
            processPath: path,
            processBundleId: bundle,
            localPort: lport,
            remoteHost: rip,
            remoteIP: rip,
            remotePort: rport,
            direction: .outgoing,
            status: .established,
            protocolName: "tcp"
        )
    }

    private func splitHostPort(_ s: String) -> (String, Int)? {
        if s.hasPrefix("[") {
            guard let close = s.firstIndex(of: "]") else { return nil }
            let host = String(s[s.index(after: s.startIndex)..<close])
            let after = s.index(after: close)
            guard after < s.endIndex, s[after] == ":" else { return nil }
            let port = Int(s[s.index(after: after)...]) ?? 0
            return (host, port)
        }
        guard let lastColon = s.lastIndex(of: ":") else { return nil }
        let host = String(s[s.startIndex..<lastColon])
        let portStr = s[s.index(after: lastColon)...]
        return (host, Int(portStr) ?? 0)
    }

    private func pidPath(_ pid: Int32) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-p", String(pid), "-o", "comm="]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func bundleID(forPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var p = path
        if let r = p.range(of: ".app/", options: .backwards) { p = String(p[..<r.upperBound]) }
        let plist = (p as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plist)) else { return nil }
        guard let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return d["CFBundleIdentifier"] as? String
    }

    private func startNettop() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-P", "-x", "-L", "0", "-J", "bytes_in,bytes_out", "-s", "1"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { PSLog.error(PSLog.netmon, "nettop failed: \(error)"); return }
        nettopProc = p

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            guard let s = String(data: data, encoding: .utf8) else { return }
            self.parseNettop(s)
        }
    }

    private func parseNettop(_ chunk: String) {
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0
        var cumulative: [Int32: (name: String, in: Int64, out: Int64)] = [:]

        for line in chunk.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("bytes_") { continue }
            let parts = trimmed.split(separator: ",").map(String.init)
            guard parts.count >= 3 else { continue }
            guard let bytesIn = Int64(parts[parts.count - 2]),
                  let bytesOut = Int64(parts[parts.count - 1]) else { continue }

            let processField = parts[0]
            let (name, pid) = parseProcessField(processField)
            guard pid > 0 else { continue }

            cumulative[pid] = (name, bytesIn, bytesOut)
            totalIn += bytesIn
            totalOut += bytesOut
        }

        let now = Date()
        let dt = now.timeIntervalSince(lastSampleTime)
        if dt >= 0.4 {
            let deltaIn = max(0, totalIn - lastIn)
            let deltaOut = max(0, totalOut - lastOut)
            lastIn = totalIn
            lastOut = totalOut
            lastSampleTime = now
            let sample = TrafficSample(
                timestamp: now,
                bytesIn: Int64(Double(deltaIn) / max(dt, 1)),
                bytesOut: Int64(Double(deltaOut) / max(dt, 1))
            )
            onSample?(sample)
        }

        let processDt = now.timeIntervalSince(lastProcessSampleTime)
        if lastProcessBytes.isEmpty {
            lastProcessBytes = cumulative.mapValues { ($0.in, $0.out) }
            lastProcessSampleTime = now
            return
        }
        guard processDt >= 0.4, !cumulative.isEmpty else { return }

        var samples: [ProcessTrafficSample] = []
        for (pid, entry) in cumulative {
            let previous = lastProcessBytes[pid] ?? (0, 0)
            let deltaIn = max(0, entry.in - previous.in)
            let deltaOut = max(0, entry.out - previous.out)
            let rateIn = Int64(Double(deltaIn) / max(processDt, 1))
            let rateOut = Int64(Double(deltaOut) / max(processDt, 1))
            if rateIn > 0 || rateOut > 0 {
                samples.append(ProcessTrafficSample(
                    pid: pid,
                    processName: entry.name,
                    bytesInRate: rateIn,
                    bytesOutRate: rateOut
                ))
            }
        }

        lastProcessBytes = cumulative.mapValues { ($0.in, $0.out) }
        lastProcessSampleTime = now
        if !samples.isEmpty {
            onProcessTraffic?(samples)
        }
    }

    private func parseProcessField(_ field: String) -> (String, Int32) {
        guard let dot = field.lastIndex(of: ".") else { return (field, 0) }
        let name = String(field[..<dot])
        let pidStr = String(field[field.index(after: dot)...])
        return (name, Int32(pidStr) ?? 0)
    }
}
