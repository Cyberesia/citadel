import Foundation

enum FortressMapProjection: String, CaseIterable, Identifiable, Sendable {
    case flat
    case globe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flat: return "2D"
        case .globe: return "3D"
        }
    }

    var systemImage: String {
        switch self {
        case .flat: return "map"
        case .globe: return "globe.americas.fill"
        }
    }
}

enum FortressFlowArcBuilder {
    /// Builds map arcs collapsed by destination so the same city isn't labeled N times.
    static func build(
        from streams: [NetworkStream],
        origin: FortressGeoPoint,
        highlightStreamID: String? = nil
    ) -> [FortressFlowArc] {
        var groups: [String: (
            dest: FortressGeoPoint,
            label: String,
            subtitle: String?,
            process: String?,
            familyID: String?,
            streamID: String?,
            rateIn: Int64,
            rateOut: Int64,
            bytesIn: Int64,
            bytesOut: Int64,
            status: StreamStatus,
            isAgent: Bool,
            familyCount: Set<String>
        )] = [:]

        for stream in streams {
            guard let dest = destination(for: stream) else { continue }
            // Destination-only key → one arc / one label per city.
            let key = "\(dest.latitude.rounded(to: 1))|\(dest.longitude.rounded(to: 1))"
            var entry = groups[key] ?? (
                dest: dest,
                label: stream.geo?.displayLabel
                    ?? (stream.remoteHost.isEmpty ? stream.remoteIP : stream.remoteHost),
                subtitle: nil,
                process: stream.process.familyName,
                familyID: stream.process.familyID,
                streamID: stream.id,
                rateIn: 0,
                rateOut: 0,
                bytesIn: 0,
                bytesOut: 0,
                status: stream.status,
                isAgent: stream.process.role == .agent,
                familyCount: []
            )
            entry.rateIn += stream.rateIn
            entry.rateOut += stream.rateOut
            entry.bytesIn += stream.bytesIn
            entry.bytesOut += stream.bytesOut
            entry.familyCount.insert(stream.process.familyID)
            if stream.status == .denied { entry.status = .denied }
            else if stream.status == .pending && entry.status != .denied { entry.status = .pending }
            if stream.process.role == .agent { entry.isAgent = true }
            if highlightStreamID == stream.id {
                entry.streamID = stream.id
                entry.process = stream.process.familyName
                entry.familyID = stream.process.familyID
            }
            // Prefer city label from geo when available
            if let geo = stream.geo, !geo.displayLabel.isEmpty {
                entry.label = geo.displayLabel
            }
            groups[key] = entry
        }

        return groups.map { (key, entry) in
                let subtitle: String?
                if entry.familyCount.count > 1 {
                    subtitle = "\(entry.familyCount.count) apps"
                } else {
                    subtitle = entry.process
                }
                return FortressFlowArc(
                    id: StableArcID.uuid(from: key),
                    origin: origin,
                    destination: entry.dest,
                    bytesIn: entry.bytesIn,
                    bytesOut: entry.bytesOut,
                    rateIn: entry.rateIn,
                    rateOut: entry.rateOut,
                    status: entry.status,
                    label: entry.label,
                    subtitle: subtitle,
                    processName: entry.process,
                    familyID: entry.familyID,
                    streamID: entry.streamID,
                    isAgent: entry.isAgent
                )
            }
            .sorted { $0.displayTraffic > $1.displayTraffic }
            .prefix(24)
            .map { $0 }
    }

    private static func destination(for stream: NetworkStream) -> FortressGeoPoint? {
        if let geo = stream.geo, let lat = geo.latitude, let lon = geo.longitude {
            return FortressGeoPoint(latitude: lat, longitude: lon)
        }
        if let code = stream.geo?.countryCode,
           let point = CountryCentroids.point(for: code) {
            return FortressGeoPoint(latitude: point.latitude, longitude: point.longitude)
        }
        return nil
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = Darwin.pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
