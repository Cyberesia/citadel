import Foundation

struct GeoPoint: Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    static let defaultOrigin = GeoPoint(latitude: 45.5017, longitude: -73.5673)
}

struct FlowArc: Identifiable, Equatable, Sendable {
    let id: UUID
    let origin: GeoPoint
    let destination: GeoPoint
    let bytesIn: Int64
    let bytesOut: Int64
    let bytesInRate: Int64
    let bytesOutRate: Int64
    let status: Connection.Status
    let label: String
    let subtitle: String?
    let processName: String?
    /// True when the flow belongs to the Cowork agent backend.
    let isAgent: Bool

    /// Stable identity across telemetry refreshes — used so pulse animations aren't reset.
    var stableKey: String { id.uuidString }

    var bytesTotal: Int64 { bytesIn + bytesOut }
    var rateTotal: Int64 { bytesInRate + bytesOutRate }

    var displayTraffic: Int64 {
        rateTotal > 0 ? rateTotal : bytesTotal
    }

    var strokeColor: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch status {
        case .denied:
            return (0.95, 0.28, 0.28, 0.92)
        case .pending:
            return (1.0, 0.72, 0.25, 0.88)
        default:
            if isAgent {
                return (0.55, 0.38, 1.0, 0.88)   // Cowork agent violet
            }
            if bytesOut >= bytesIn {
                return (1.0, 0.72, 0.35, 0.82)   // outbound gold
            }
            return (1.0, 0.44, 0.26, 0.82)       // inbound rust
        }
    }

    var lineWidth: CGFloat {
        let mb = Double(max(displayTraffic, 1)) / 1_000_000
        if displayTraffic > 0 {
            return CGFloat(min(3.0, max(0.85, 0.75 + log10(max(mb, 0.05)) * 0.65)))
        }
        return 1.1
    }
}

/// Deterministic UUID from a stable arc key so refreshes don't mint new identities.
enum StableArcID {
    static func uuid(from key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let data = Array(key.utf8)
        // FNV-1a 128-bit style fold into 16 bytes
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for (i, byte) in data.enumerated() {
            hash ^= UInt64(byte)
            hash = hash &* prime
            bytes[i % 16] ^= UInt8(truncatingIfNeeded: hash)
            bytes[(i + 7) % 16] ^= UInt8(truncatingIfNeeded: hash >> 8)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40 // UUID version 4 shape
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
