import Foundation

/// Snapshot of an open socket endpoint before identity enrichment.
public struct SocketEndpoint: Sendable, Hashable {
    public let pid: pid_t
    public let processName: String
    public let localHost: String
    public let localPort: Int
    public let remoteHost: String
    public let remotePort: Int
    public let protocolName: String

    public init(
        pid: pid_t,
        processName: String,
        localHost: String = "",
        localPort: Int = 0,
        remoteHost: String,
        remotePort: Int,
        protocolName: String = "tcp"
    ) {
        self.pid = pid
        self.processName = processName
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.protocolName = protocolName
    }
}

/// Collects open internet sockets via `lsof` field output as a reliable
/// unprivileged fallback. Parses once per tick (no per-connection `ps`).
public final class SocketInventorySource: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.citadel.sentinel.sockets", qos: .utility)

    public init() {}

    public func snapshot() -> [SocketEndpoint] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // Field output: p=pid, c=command, n=name, P=protocol
        process.arguments = ["-i", "-n", "-P", "-F", "pcnP"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parseLsof(text)
    }

    private func parseLsof(_ text: String) -> [SocketEndpoint] {
        var endpoints: [SocketEndpoint] = []
        var pid: pid_t = 0
        var name = ""
        var proto = "tcp"

        for line in text.split(separator: "\n") {
            guard let first = line.first else { continue }
            let rest = String(line.dropFirst())
            switch first {
            case "p":
                pid = pid_t(rest) ?? 0
            case "c":
                name = rest
            case "P":
                proto = rest.lowercased()
            case "n":
                if let ep = parseName(rest, pid: pid, name: name, proto: proto) {
                    endpoints.append(ep)
                }
            default:
                break
            }
        }
        return endpoints
    }

    private func parseName(_ line: String, pid: pid_t, name: String, proto: String) -> SocketEndpoint? {
        guard pid > 0, line.contains("->") else { return nil }
        let parts = line.split(separator: " ").map(String.init)
        let addrPart = parts.first ?? line
        let halves = addrPart.split(separator: "-", maxSplits: 1).map(String.init)
        guard halves.count == 2 else { return nil }
        let local = halves[0]
        let remoteRaw = halves[1].hasPrefix(">") ? String(halves[1].dropFirst()) : halves[1]
        guard let (lip, lport) = splitHostPort(local),
              let (rip, rport) = splitHostPort(remoteRaw) else { return nil }
        // Skip loopback-only noise for clarity
        if rip == "127.0.0.1" || rip == "::1" { return nil }
        return SocketEndpoint(
            pid: pid,
            processName: name,
            localHost: lip,
            localPort: lport,
            remoteHost: rip,
            remotePort: rport,
            protocolName: proto
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
}
