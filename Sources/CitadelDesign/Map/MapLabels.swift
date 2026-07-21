import Foundation

struct MapPlace: Sendable {
    enum Kind: Sendable {
        case country
        case city
    }

    let name: String
    let point: GeoPoint
    let kind: Kind
    /// Minimum flat-map zoom level before this label is drawn.
    let minZoom: CGFloat
}

/// Static geographic labels for the flat map (until we adopt vector tiles).
enum MapLabels {
    static let all: [MapPlace] = countries + cities

    private static let countries: [MapPlace] = [
        place("United States", 39.0, -98.0, .country, 1.0),
        place("Canada", 56.0, -96.0, .country, 1.2),
        place("Mexico", 23.6, -102.5, .country, 1.4),
        place("Brazil", -10.0, -55.0, .country, 1.2),
        place("Argentina", -34.0, -64.0, .country, 1.6),
        place("United Kingdom", 54.0, -2.5, .country, 1.4),
        place("France", 46.5, 2.5, .country, 1.3),
        place("Germany", 51.2, 10.5, .country, 1.3),
        place("Italy", 42.5, 12.5, .country, 1.3),
        place("Spain", 40.0, -4.0, .country, 1.4),
        place("Switzerland", 46.8, 8.2, .country, 1.5),
        place("Netherlands", 52.2, 5.3, .country, 1.8),
        place("Sweden", 62.0, 15.0, .country, 1.6),
        place("Norway", 64.0, 12.0, .country, 1.6),
        place("Poland", 52.0, 19.5, .country, 1.5),
        place("Ukraine", 49.0, 32.0, .country, 1.5),
        place("Russia", 60.0, 90.0, .country, 1.0),
        place("Turkey", 39.0, 35.0, .country, 1.4),
        place("Egypt", 26.8, 30.8, .country, 1.5),
        place("South Africa", -29.0, 24.0, .country, 1.4),
        place("India", 22.0, 79.0, .country, 1.2),
        place("China", 35.0, 104.0, .country, 1.0),
        place("Japan", 36.2, 138.2, .country, 1.3),
        place("South Korea", 36.5, 127.8, .country, 1.8),
        place("Australia", -25.0, 133.0, .country, 1.2),
        place("Indonesia", -2.5, 118.0, .country, 1.4),
        place("Saudi Arabia", 24.0, 45.0, .country, 1.6),
        place("UAE", 24.0, 54.0, .country, 1.8),
        place("Israel", 31.5, 34.8, .country, 2.0),
    ]

    private static let cities: [MapPlace] = [
        place("New York", 40.7, -74.0, .city, 2.2),
        place("Washington", 38.9, -77.0, .city, 2.4),
        place("Ashburn", 39.0, -77.5, .city, 3.2),
        place("San Francisco", 37.8, -122.4, .city, 2.4),
        place("Los Angeles", 34.0, -118.2, .city, 2.4),
        place("Chicago", 41.9, -87.6, .city, 2.6),
        place("Seattle", 47.6, -122.3, .city, 2.8),
        place("Toronto", 43.7, -79.4, .city, 2.6),
        place("Montréal", 45.5, -73.6, .city, 2.8),
        place("São Paulo", -23.5, -46.6, .city, 2.6),
        place("London", 51.5, -0.1, .city, 2.2),
        place("Paris", 48.9, 2.3, .city, 2.4),
        place("Berlin", 52.5, 13.4, .city, 2.6),
        place("Frankfurt", 50.1, 8.7, .city, 2.8),
        place("Amsterdam", 52.4, 4.9, .city, 2.8),
        place("Zürich", 47.4, 8.5, .city, 2.4),
        place("Geneva", 46.2, 6.1, .city, 3.0),
        place("Milan", 45.5, 9.2, .city, 2.8),
        place("Rome", 41.9, 12.5, .city, 2.8),
        place("Madrid", 40.4, -3.7, .city, 2.8),
        place("Stockholm", 59.3, 18.1, .city, 3.0),
        place("Warsaw", 52.2, 21.0, .city, 3.0),
        place("Moscow", 55.8, 37.6, .city, 2.4),
        place("Istanbul", 41.0, 29.0, .city, 2.8),
        place("Dubai", 25.2, 55.3, .city, 2.8),
        place("Mumbai", 19.1, 72.9, .city, 2.6),
        place("Singapore", 1.3, 103.8, .city, 2.8),
        place("Tokyo", 35.7, 139.7, .city, 2.4),
        place("Seoul", 37.6, 127.0, .city, 2.8),
        place("Hong Kong", 22.3, 114.2, .city, 2.8),
        place("Shanghai", 31.2, 121.5, .city, 2.6),
        place("Beijing", 39.9, 116.4, .city, 2.6),
        place("Sydney", -33.9, 151.2, .city, 2.6),
        place("Melbourne", -37.8, 145.0, .city, 3.0),
        place("Cairo", 30.0, 31.2, .city, 2.8),
        place("Johannesburg", -26.2, 28.0, .city, 3.0),
    ]

    static func visible(zoom: CGFloat) -> [MapPlace] {
        all.filter { zoom >= $0.minZoom }
    }

    private static func place(
        _ name: String,
        _ lat: Double,
        _ lon: Double,
        _ kind: MapPlace.Kind,
        _ minZoom: CGFloat
    ) -> MapPlace {
        MapPlace(name: name, point: GeoPoint(latitude: lat, longitude: lon), kind: kind, minZoom: minZoom)
    }
}
