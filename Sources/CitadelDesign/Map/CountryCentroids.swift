import Foundation

/// Approximate country centroids for geo lookup when IP geolocation is unavailable.
enum CountryCentroids {
    private static let points: [String: GeoPoint] = [
        "US": GeoPoint(latitude: 39.8283, longitude: -98.5795),
        "CA": GeoPoint(latitude: 56.1304, longitude: -106.3468),
        "GB": GeoPoint(latitude: 55.3781, longitude: -3.4360),
        "DE": GeoPoint(latitude: 51.1657, longitude: 10.4515),
        "FR": GeoPoint(latitude: 46.2276, longitude: 2.2137),
        "NL": GeoPoint(latitude: 52.1326, longitude: 5.2913),
        "SE": GeoPoint(latitude: 60.1282, longitude: 18.6435),
        "IE": GeoPoint(latitude: 53.4129, longitude: -8.2439),
        "JP": GeoPoint(latitude: 36.2048, longitude: 138.2529),
        "SG": GeoPoint(latitude: 1.3521, longitude: 103.8198),
        "AU": GeoPoint(latitude: -25.2744, longitude: 133.7751),
        "BR": GeoPoint(latitude: -14.2350, longitude: -51.9253),
        "IN": GeoPoint(latitude: 20.5937, longitude: 78.9629),
        "CN": GeoPoint(latitude: 35.8617, longitude: 104.1954),
        "RU": GeoPoint(latitude: 61.5240, longitude: 105.3188),
        "KR": GeoPoint(latitude: 35.9078, longitude: 127.7669),
        "FI": GeoPoint(latitude: 61.9241, longitude: 25.7482),
        "CH": GeoPoint(latitude: 46.8182, longitude: 8.2275),
        "AE": GeoPoint(latitude: 23.4241, longitude: 53.8478),
        "IL": GeoPoint(latitude: 31.0461, longitude: 34.8516),
        "UA": GeoPoint(latitude: 48.3794, longitude: 31.1656),
    ]

    static func point(for countryCode: String) -> GeoPoint? {
        points[countryCode.uppercased()]
    }
}
