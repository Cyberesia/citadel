import Foundation

/// Fortress geo façade over the shared `IPGeoCache` (one network geo stack for the app).
public actor GeoResolver {
    public static let shared = GeoResolver()

    public func cached(_ ip: String) async -> FortressGeoLocation? {
        guard let entry = await IPGeoCache.shared.cached(ip) else { return nil }
        return Self.toFortress(entry)
    }

    public func lookupBatch(_ ips: [String]) async -> [String: FortressGeoLocation] {
        let pending = ips.filter { GeoLookup.isPublicIP($0) }
        guard !pending.isEmpty else { return [:] }
        let resolved = await IPGeoCache.shared.lookupBatch(pending)
        return resolved.mapValues { Self.toFortress($0) }
    }

    public func lookupSelf() async -> FortressGeoLocation? {
        guard let entry = await IPGeoCache.shared.lookupSelf() else { return nil }
        return Self.toFortress(entry)
    }

    public static func isPublicIP(_ raw: String) -> Bool {
        GeoLookup.isPublicIP(raw)
    }

    private static func toFortress(_ entry: IPGeoCache.Entry) -> FortressGeoLocation {
        FortressGeoLocation(
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
