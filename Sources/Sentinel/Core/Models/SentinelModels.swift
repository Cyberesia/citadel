import Foundation
import AppKit

// MARK: - Focus

/// Hierarchical navigation focus for Sentinel (sidebar → map → inspector).
public enum MonitorFocus: Equatable, Hashable, Sendable {
    case all
    case family(String)
    case role(familyID: String, role: ProcessRole)
    /// Remote site/host under an app family (best proxy for “which tab” — OS has no tab titles).
    case host(familyID: String, hostKey: String)
    case stream(id: String)
}

// MARK: - Identity

public struct ProcessIdentity: Hashable, Sendable, Identifiable {
    public var id: String { "\(pid)" }
    public let pid: pid_t
    public let ppid: pid_t?
    public let name: String
    public let path: String
    public let bundleID: String?
    public let familyID: String
    public let familyName: String
    public let role: ProcessRole

    public init(
        pid: pid_t,
        ppid: pid_t? = nil,
        name: String,
        path: String = "",
        bundleID: String? = nil,
        familyID: String,
        familyName: String,
        role: ProcessRole = .unknown
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.path = path
        self.bundleID = bundleID
        self.familyID = familyID
        self.familyName = familyName
        self.role = role
    }
}

// MARK: - Geo

public struct SentinelGeoLocation: Hashable, Sendable {
    public let ip: String
    public let country: String?
    public let countryCode: String?
    public let city: String?
    public let region: String?
    public let latitude: Double?
    public let longitude: Double?
    public let reverseHost: String?
    public let org: String?

    public var isValid: Bool { latitude != nil && longitude != nil }

    public init(
        ip: String,
        country: String? = nil,
        countryCode: String? = nil,
        city: String? = nil,
        region: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        reverseHost: String? = nil,
        org: String? = nil
    ) {
        self.ip = ip
        self.country = country
        self.countryCode = countryCode
        self.city = city
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.reverseHost = reverseHost
        self.org = org
    }

    public var displayLabel: String {
        if let city, let country, !city.isEmpty { return "\(city), \(country)" }
        if let city, !city.isEmpty { return city }
        if let country, !country.isEmpty { return country }
        return ip
    }
}

public struct SentinelGeoPoint: Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public static let defaultOrigin = SentinelGeoPoint(latitude: 45.5017, longitude: -73.5673)

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Stream

public enum StreamStatus: String, Codable, Sendable, Hashable {
    case allowed
    case denied
    case pending
    case established
    case closed
}

public struct NetworkStream: Identifiable, Hashable, Sendable {
    public let id: String
    public var process: ProcessIdentity
    public var remoteHost: String
    public var remoteIP: String
    public var remotePort: Int
    public var protocolName: String
    public var bytesIn: Int64
    public var bytesOut: Int64
    public var rateIn: Int64
    public var rateOut: Int64
    public var status: StreamStatus
    public var geo: SentinelGeoLocation?
    public var firstSeen: Date
    public var lastSeen: Date

    public var rateTotal: Int64 { rateIn + rateOut }
    public var bytesTotal: Int64 { bytesIn + bytesOut }

    /// Stable key for site rollups / focus (registrable domain when known, else IP).
    public var remoteKey: String {
        if let name = resolvedHostname {
            return Self.registrableDomain(name)
        }
        return remoteIP
    }

    /// User-facing remote label (prefer website hostname over raw IP).
    public var remoteDisplayName: String {
        if let name = resolvedHostname {
            return Self.registrableDomain(name)
        }
        return remoteIP
    }

    /// Full hostname when known (not collapsed), for detail panes.
    public var remoteHostFull: String {
        resolvedHostname ?? remoteIP
    }

    /// Best hostname signal: DNS bridge / PTR on `remoteHost`, else geo provider reverse.
    public var resolvedHostnameForDisplay: String? { resolvedHostname }

    private var resolvedHostname: String? {
        let host = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty, host != remoteIP, !Self.looksLikeIP(host) {
            return host
        }
        if let reverse = geo?.reverseHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reverse.isEmpty, !Self.looksLikeIP(reverse) {
            return reverse
        }
        return nil
    }

    public init(
        id: String,
        process: ProcessIdentity,
        remoteHost: String = "",
        remoteIP: String,
        remotePort: Int = 0,
        protocolName: String = "tcp",
        bytesIn: Int64 = 0,
        bytesOut: Int64 = 0,
        rateIn: Int64 = 0,
        rateOut: Int64 = 0,
        status: StreamStatus = .established,
        geo: SentinelGeoLocation? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.process = process
        self.remoteHost = remoteHost
        self.remoteIP = remoteIP
        self.remotePort = remotePort
        self.protocolName = protocolName
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.rateIn = rateIn
        self.rateOut = rateOut
        self.status = status
        self.geo = geo
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    public static func makeID(pid: pid_t, remoteIP: String, remotePort: Int, proto: String) -> String {
        "\(pid)|\(remoteIP)|\(remotePort)|\(proto)"
    }

    public static func looksLikeIP(_ value: String) -> Bool {
        if value.contains(":") { return true } // IPv6
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { UInt8($0) != nil }
    }

    /// Collapse `a.b.facebook.com` → `facebook.com` for Sites labels.
    public static func registrableDomain(_ host: String) -> String {
        let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        if looksLikeIP(cleaned) { return cleaned }
        let parts = cleaned.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return cleaned }
        let multi: Set<String> = [
            "co.uk", "org.uk", "ac.uk", "gov.uk",
            "com.au", "net.au", "org.au",
            "co.jp", "co.kr", "com.br", "com.mx",
            "co.nz", "co.za", "com.sg", "com.hk"
        ]
        let last2 = parts.suffix(2).joined(separator: ".")
        if multi.contains(last2), parts.count >= 3 {
            return parts.suffix(3).joined(separator: ".")
        }
        return last2
    }
}

// MARK: - Tree

public struct ProcessFamilyNode: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case family
        case roleGroup(ProcessRole)
        case process
        /// Container for remotes under an app (site / host — proxy for browser tabs).
        case sites
        /// Aggregated remotes under an app.
        case host
        case stream
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String?
    public let rateIn: Int64
    public let rateOut: Int64
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let connectionCount: Int
    public let children: [ProcessFamilyNode]
    public let streamID: String?
    public let familyID: String?
    public let hostKey: String?
    public let role: ProcessRole?
    public let isAgent: Bool

    public var rateTotal: Int64 { rateIn + rateOut }
    public var bytesTotal: Int64 { bytesIn + bytesOut }

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        rateIn: Int64 = 0,
        rateOut: Int64 = 0,
        bytesIn: Int64 = 0,
        bytesOut: Int64 = 0,
        connectionCount: Int = 0,
        children: [ProcessFamilyNode] = [],
        streamID: String? = nil,
        familyID: String? = nil,
        hostKey: String? = nil,
        role: ProcessRole? = nil,
        isAgent: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.rateIn = rateIn
        self.rateOut = rateOut
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.connectionCount = connectionCount
        self.children = children
        self.streamID = streamID
        self.familyID = familyID
        self.hostKey = hostKey
        self.role = role
        self.isAgent = isAgent
    }
}

// MARK: - Bandwidth

public struct BandwidthRate: Hashable, Sendable {
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let timestamp: Date

    public init(bytesIn: Int64, bytesOut: Int64, timestamp: Date = Date()) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.timestamp = timestamp
    }
}

public struct ProcessBandwidth: Hashable, Sendable {
    public let pid: pid_t
    public let processName: String
    public let rateIn: Int64
    public let rateOut: Int64

    public init(pid: pid_t, processName: String, rateIn: Int64, rateOut: Int64) {
        self.pid = pid
        self.processName = processName
        self.rateIn = rateIn
        self.rateOut = rateOut
    }
}

// MARK: - Map arc

public struct SentinelFlowArc: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let origin: SentinelGeoPoint
    public let destination: SentinelGeoPoint
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let rateIn: Int64
    public let rateOut: Int64
    public let status: StreamStatus
    public let label: String
    public let subtitle: String?
    public let processName: String?
    public let familyID: String?
    public let streamID: String?
    public let isAgent: Bool

    public var rateTotal: Int64 { rateIn + rateOut }
    public var bytesTotal: Int64 { bytesIn + bytesOut }
    public var displayTraffic: Int64 { rateTotal > 0 ? rateTotal : bytesTotal }

    public init(
        id: UUID = UUID(),
        origin: SentinelGeoPoint,
        destination: SentinelGeoPoint,
        bytesIn: Int64 = 0,
        bytesOut: Int64 = 0,
        rateIn: Int64 = 0,
        rateOut: Int64 = 0,
        status: StreamStatus = .established,
        label: String,
        subtitle: String? = nil,
        processName: String? = nil,
        familyID: String? = nil,
        streamID: String? = nil,
        isAgent: Bool = false
    ) {
        self.id = id
        self.origin = origin
        self.destination = destination
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.rateIn = rateIn
        self.rateOut = rateOut
        self.status = status
        self.label = label
        self.subtitle = subtitle
        self.processName = processName
        self.familyID = familyID
        self.streamID = streamID
        self.isAgent = isAgent
    }

    public var strokeColor: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch status {
        case .denied: return (0.95, 0.28, 0.28, 0.92)
        case .pending: return (1.0, 0.72, 0.25, 0.88)
        default:
            if isAgent { return (0.55, 0.38, 1.0, 0.88) }
            if bytesOut >= bytesIn { return (1.0, 0.72, 0.35, 0.82) }
            return (1.0, 0.44, 0.26, 0.82)
        }
    }

    public var lineWidth: CGFloat {
        let mb = Double(max(displayTraffic, 1)) / 1_000_000
        if displayTraffic > 0 {
            return CGFloat(min(3.0, max(0.85, 0.75 + log10(max(mb, 0.05)) * 0.65)))
        }
        return 1.1
    }
}

// MARK: - Alerts / rollups

public struct SentinelAlert: Identifiable {
    public let id = UUID()
    public let stream: NetworkStream
    public let reply: (Bool, Bool) -> Void
}

public struct SentinelRollup: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let rateTotal: Int64
    public let bytesTotal: Int64
    public let connectionCount: Int

    public init(id: String, label: String, rateTotal: Int64 = 0, bytesTotal: Int64 = 0, connectionCount: Int = 0) {
        self.id = id
        self.label = label
        self.rateTotal = rateTotal
        self.bytesTotal = bytesTotal
        self.connectionCount = connectionCount
    }
}

// MARK: - Formatting

enum SentinelFormat {
    static func bytes(_ n: Int64) -> String {
        let abs = Double(Swift.abs(n))
        if abs < 1024 { return "\(n) B" }
        if abs < 1024 * 1024 { return String(format: "%.1f KB", abs / 1024) }
        if abs < 1024 * 1024 * 1024 { return String(format: "%.1f MB", abs / (1024 * 1024)) }
        return String(format: "%.2f GB", abs / (1024 * 1024 * 1024))
    }

    static func bytesPerSec(_ n: Int64) -> String {
        bytes(n) + "/s"
    }
}
