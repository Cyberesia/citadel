import Foundation

/// Sentinel geo façade over the shared `IPGeoCache` (one network geo stack for the app).
public actor GeoResolver {
    public static let shared = GeoResolver()

    public func cached(_ ip: String) async -> SentinelGeoLocation? {
        guard let entry = await IPGeoCache.shared.cached(ip) else { return nil }
        return Self.toSentinel(entry)
    }

    public func lookupBatch(_ ips: [String]) async -> [String: SentinelGeoLocation] {
        let pending = ips.filter { GeoLookup.isPublicIP($0) }
        guard !pending.isEmpty else { return [:] }
        let resolved = await IPGeoCache.shared.lookupBatch(pending)
        return resolved.mapValues { Self.toSentinel($0) }
    }

    public func lookupSelf() async -> SentinelGeoLocation? {
        guard let entry = await IPGeoCache.shared.lookupSelf() else { return nil }
        return Self.toSentinel(entry)
    }

    public static func isPublicIP(_ raw: String) -> Bool {
        GeoLookup.isPublicIP(raw)
    }

    private static func toSentinel(_ entry: IPGeoCache.Entry) -> SentinelGeoLocation {
        SentinelGeoLocation(
            ip: entry.ip,
            country: entry.country,
            countryCode: entry.countryCode,
            city: entry.city,
            region: entry.region,
            latitude: entry.lat,
            longitude: entry.lon,
            reverseHost: entry.reverse,
            org: entry.org
        )
    }
}
