import Foundation

public actor IPGeoCache {
    public struct Entry: Sendable {
        public let ip: String
        public let country: String?
        public let countryCode: String?
        public let city: String?
        public let region: String?
        public let lat: Double?
        public let lon: Double?
        /// Reverse DNS from the geo provider (often better than getnameinfo for CDNs).
        public let reverse: String?
        public let org: String?

        public var isValid: Bool { lat != nil && lon != nil }
    }

    public static let shared = IPGeoCache()
    private var cache: [String: Entry] = [:]

    /// Returns whatever is already cached without hitting the network.
    public func cached(_ ip: String) -> Entry? { cache[ip] }

    /// Resolve many IPs in a single ip-api.com batch request (≤100 per call,
    /// 15 req/min limit). Far gentler than per-IP lookups, which get rate-limited.
    /// Returns a map of ip → Entry for the ones that resolved.
    public func lookupBatch(_ ips: [String]) async -> [String: Entry] {
        var result: [String: Entry] = [:]
        // Re-fetch when we only have geo coords but never tried reverse (older cache rows).
        let pending = ips.filter { ip in
            guard let cached = cache[ip] else { return true }
            if !cached.isValid { return true }
            return false
        }
        for ip in ips {
            if let cached = cache[ip], cached.isValid {
                result[ip] = cached
            }
        }
        guard !pending.isEmpty else { return result }

        for chunk in pending.chunked(into: 100) {
            if let resolved = await fetchIPAPIBatch(chunk) {
                for (ip, entry) in resolved {
                    cache[ip] = entry
                    result[ip] = entry
                }
            }
        }
        return result
    }

    /// Resolves the public IP and location of this Mac.
    public func lookupSelf() async -> Entry? {
        if let cached = cache["__self__"], cached.isValid { return cached }
        // ip-api own-IP endpoint first, ipwho.is as fallback.
        var entry = await fetchIPAPISelf()
        if entry == nil { entry = await fetchIPWhoisSelf() }
        if let entry {
            cache["__self__"] = entry
            return entry
        }
        return nil
    }

    // MARK: - ip-api.com (HTTP, batch capable, primary)

    private func fetchIPAPIBatch(_ ips: [String]) async -> [String: Entry]? {
        let fields = "status,country,countryCode,city,regionName,lat,lon,query,reverse,org"
        guard let url = URL(string: "http://ip-api.com/batch?fields=\(fields)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ips)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            var out: [String: Entry] = [:]
            for obj in arr {
                guard obj["status"] as? String == "success",
                      let ip = obj["query"] as? String else { continue }
                let reverse = (obj["reverse"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let entry = Entry(
                    ip: ip,
                    country: obj["country"] as? String,
                    countryCode: obj["countryCode"] as? String,
                    city: obj["city"] as? String,
                    region: obj["regionName"] as? String,
                    lat: number(obj["lat"]),
                    lon: number(obj["lon"]),
                    reverse: (reverse?.isEmpty == false) ? reverse : nil,
                    org: obj["org"] as? String
                )
                if entry.isValid { out[ip] = entry }
            }
            return out
        } catch {
            return nil
        }
    }

    private func fetchIPAPISelf() async -> Entry? {
        let fields = "status,country,countryCode,city,regionName,lat,lon,query,reverse,org"
        guard let url = URL(string: "http://ip-api.com/json/?fields=\(fields)") else { return nil }
        return await fetchObject(url: url) { obj in
            guard obj["status"] as? String == "success" else { return nil }
            let reverse = (obj["reverse"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Entry(
                ip: obj["query"] as? String ?? "__self__",
                country: obj["country"] as? String,
                countryCode: obj["countryCode"] as? String,
                city: obj["city"] as? String,
                region: obj["regionName"] as? String,
                lat: number(obj["lat"]),
                lon: number(obj["lon"]),
                reverse: (reverse?.isEmpty == false) ? reverse : nil,
                org: obj["org"] as? String
            )
        }
    }

    // MARK: - ipwho.is (HTTPS, fallback for self)

    private func fetchIPWhoisSelf() async -> Entry? {
        guard let url = URL(string: "https://ipwho.is/") else { return nil }
        return await fetchObject(url: url) { obj in
            guard obj["success"] as? Bool == true else { return nil }
            return Entry(
                ip: obj["ip"] as? String ?? "__self__",
                country: obj["country"] as? String,
                countryCode: obj["country_code"] as? String,
                city: obj["city"] as? String,
                region: obj["region"] as? String,
                lat: number(obj["latitude"]),
                lon: number(obj["longitude"]),
                reverse: nil,
                org: nil
            )
        }
    }

    // MARK: - Helpers

    private func fetchObject(url: URL, parse: ([String: Any]) -> Entry?) async -> Entry? {
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "GET"
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = parse(json), entry.isValid else { return nil }
            return entry
        } catch {
            return nil
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

enum GeoLookup {
    static func isPublicIP(_ raw: String) -> Bool {
        let ip = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ip.isEmpty { return false }

        if ip.contains(":") {
            let lower = ip.lowercased()
            if lower == "::1" { return false }
            if lower.hasPrefix("fe80:") || lower.hasPrefix("fc") || lower.hasPrefix("fd") { return false }
            return true
        }

        if ip.hasPrefix("127.") || ip.hasPrefix("10.") || ip.hasPrefix("192.168.") { return false }
        if ip.hasPrefix("169.254.") || ip == "0.0.0.0" { return false }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), second >= 16, second <= 31 { return false }
        }
        return ip.first?.isNumber == true
    }

    static func apply(_ entry: IPGeoCache.Entry, to connection: Connection) -> Connection {
        var copy = connection
        copy.country = entry.country
        copy.countryCode = entry.countryCode
        copy.city = entry.city
        copy.region = entry.region
        copy.latitude = entry.lat
        copy.longitude = entry.lon
        return copy
    }
}
