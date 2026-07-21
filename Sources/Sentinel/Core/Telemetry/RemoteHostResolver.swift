import Foundation
import Darwin

/// Async reverse-DNS cache so Activity can show site hostnames instead of raw IPs.
/// OS sockets never expose browser tab titles — hostname is the best available signal.
public final class RemoteHostResolver: @unchecked Sendable {
    public static let shared = RemoteHostResolver()

    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private var inFlight: Set<String> = []
    private var negativeUntil: [String: Date] = [:]

    private init() {}

    public func cachedHost(for ip: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[ip]
    }

    /// Resolve a batch of IPs. Returns only newly resolved (or refreshed) mappings.
    public func lookupBatch(_ ips: [String]) async -> [String: String] {
        var pending: [String] = []
        lock.lock()
        let now = Date()
        for ip in ips {
            guard isIPv4or6(ip) else { continue }
            if cache[ip] != nil { continue }
            if let until = negativeUntil[ip], until > now { continue }
            if inFlight.contains(ip) { continue }
            inFlight.insert(ip)
            pending.append(ip)
        }
        lock.unlock()

        guard !pending.isEmpty else { return [:] }

        var resolved: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for ip in pending.prefix(24) {
                group.addTask {
                    let host = await Self.reverseLookup(ip)
                    return (ip, host)
                }
            }
            for await (ip, host) in group {
                lock.lock()
                inFlight.remove(ip)
                if let host, !host.isEmpty, host != ip {
                    cache[ip] = host
                    resolved[ip] = host
                } else {
                    negativeUntil[ip] = Date().addingTimeInterval(120)
                }
                lock.unlock()
            }
        }
        return resolved
    }

    private static func reverseLookup(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo(
                    ai_flags: AI_NUMERICHOST,
                    ai_family: AF_UNSPEC,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: 0,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil
                )
                var info: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(ip, nil, &hints, &info) == 0, let info else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(info) }

                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(
                    info.pointee.ai_addr,
                    info.pointee.ai_addrlen,
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
                guard status == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let host = String(cString: hostBuffer)
                continuation.resume(returning: host.isEmpty ? nil : host)
            }
        }
    }

    private func isIPv4or6(_ s: String) -> Bool {
        s.contains(".") || s.contains(":")
    }
}
