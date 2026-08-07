import Foundation

public struct Connection: Identifiable, Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case allowed, denied, pending, established, closed
    }

    public var id: UUID
    public var pid: Int32
    public var processName: String
    public var processPath: String
    public var processBundleId: String?
    public var codeTeamID: String?
    public var signingStatus: ProcessSigningStatus
    public var localPort: Int
    public var remoteHost: String
    public var remoteIP: String
    public var remotePort: Int
    public var direction: RuleDirection
    public var status: Status
    public var protocolName: String
    public var bytesIn: Int64
    public var bytesOut: Int64
    public var country: String?
    public var countryCode: String?
    public var city: String?
    public var region: String?
    public var latitude: Double?
    public var longitude: Double?
    public var firstSeen: Date
    public var lastSeen: Date

    public init(
        id: UUID = UUID(),
        pid: Int32,
        processName: String,
        processPath: String,
        processBundleId: String? = nil,
        codeTeamID: String? = nil,
        signingStatus: ProcessSigningStatus = .unknown,
        localPort: Int = 0,
        remoteHost: String = "",
        remoteIP: String = "",
        remotePort: Int = 0,
        direction: RuleDirection = .outgoing,
        status: Status = .pending,
        protocolName: String = "tcp",
        bytesIn: Int64 = 0,
        bytesOut: Int64 = 0,
        country: String? = nil,
        countryCode: String? = nil,
        city: String? = nil,
        region: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.pid = pid
        self.processName = processName
        self.processPath = processPath
        self.processBundleId = processBundleId
        self.codeTeamID = codeTeamID
        self.signingStatus = signingStatus
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remoteIP = remoteIP
        self.remotePort = remotePort
        self.direction = direction
        self.status = status
        self.protocolName = protocolName
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.country = country
        self.countryCode = countryCode
        self.city = city
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

public struct TrafficSample: Codable, Sendable {
    public let timestamp: Date
    public let bytesIn: Int64
    public let bytesOut: Int64

    public init(timestamp: Date, bytesIn: Int64, bytesOut: Int64) {
        self.timestamp = timestamp
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public struct HelperStatus: Codable, Sendable {
    public let version: String
    public let running: Bool
    public let pfctlActive: Bool
    public let dnsProxyActive: Bool
    public let dnsProxyPort: Int
    public let activeRules: Int
    public let blockedToday: Int

    public init(
        version: String,
        running: Bool,
        pfctlActive: Bool,
        dnsProxyActive: Bool,
        dnsProxyPort: Int,
        activeRules: Int,
        blockedToday: Int
    ) {
        self.version = version
        self.running = running
        self.pfctlActive = pfctlActive
        self.dnsProxyActive = dnsProxyActive
        self.dnsProxyPort = dnsProxyPort
        self.activeRules = activeRules
        self.blockedToday = blockedToday
    }
}
