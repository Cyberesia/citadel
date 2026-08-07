import Foundation

/// IP → hostname map from DNS answers (helper) and optional GUI merges.
/// Best signal for real website names Chrome/etc. contacted (vs reverse PTR).
public enum SharedDNSNameBridge {
    private static let lock = NSLock()
    private static var memory: [String: String] = [:]

    private static var fileURL: URL {
        let dir = AppConstants.sharedDataDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dns-ip-names.json")
    }

    /// Record domain → resolved IPs (newest domain wins per IP).
    public static func record(domain: String, ips: [String]) {
        let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !cleaned.isEmpty, !ips.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        loadLocked()
        for ip in ips {
            let key = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            memory[key] = cleaned
        }
        persistLocked()
    }

    public static func host(forIP ip: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        loadLocked()
        return memory[ip]
    }

    /// Snapshot of IP → hostname for a batch of IPs.
    public static func hosts(forIPs ips: [String]) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        loadLocked()
        var out: [String: String] = [:]
        for ip in ips {
            if let host = memory[ip] { out[ip] = host }
        }
        return out
    }

    private static func loadLocked() {
        guard memory.isEmpty,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        memory = decoded
    }

    private static func persistLocked() {
        // Cap growth — keep a bounded set of IP → name pairs.
        if memory.count > 4000 {
            memory = Dictionary(uniqueKeysWithValues: Array(memory).suffix(3000))
        }
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
