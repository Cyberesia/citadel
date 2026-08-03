import Foundation

public struct Rule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var processBundleId: String?
    public var processPath: String?
    public var processName: String?
    public var codeTeamID: String?
    public var requiresSignature: Bool
    public var remoteHost: String?
    public var remoteIP: String?
    public var remotePort: Int?
    public var direction: RuleDirection
    public var action: RuleAction
    public var scope: RuleScope
    public var priority: Int
    public var profile: String
    public var groupName: String?
    public var notes: String?
    public var enabled: Bool
    public var temporary: Bool
    public var createdAt: Date
    public var expiresAt: Date?
    public var lastUsedAt: Date?
    public var hitCount: Int

    public init(
        id: UUID = UUID(),
        processBundleId: String? = nil,
        processPath: String? = nil,
        processName: String? = nil,
        codeTeamID: String? = nil,
        requiresSignature: Bool = false,
        remoteHost: String? = nil,
        remoteIP: String? = nil,
        remotePort: Int? = nil,
        direction: RuleDirection = .outgoing,
        action: RuleAction = .ask,
        scope: RuleScope = .domain,
        priority: Int = 100,
        profile: String = "default",
        groupName: String? = nil,
        notes: String? = nil,
        enabled: Bool = true,
        temporary: Bool = false,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        lastUsedAt: Date? = nil,
        hitCount: Int = 0
    ) {
        self.id = id
        self.processBundleId = processBundleId
        self.processPath = processPath
        self.processName = processName
        self.codeTeamID = codeTeamID
        self.requiresSignature = requiresSignature
        self.remoteHost = remoteHost
        self.remoteIP = remoteIP
        self.remotePort = remotePort
        self.direction = direction
        self.action = action
        self.scope = scope
        self.priority = priority
        self.profile = profile
        self.groupName = groupName
        self.notes = notes
        self.enabled = enabled
        self.temporary = temporary
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt
        self.hitCount = hitCount
    }
}

public struct Profile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var mode: AppMode
    public var icon: String
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        mode: AppMode = .alert,
        icon: String = "shield",
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.icon = icon
        self.isActive = isActive
    }
}

public struct BlocklistInfo: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var url: String
    public var enabled: Bool
    public var lastUpdated: Date?
    public var entryCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        enabled: Bool = true,
        lastUpdated: Date? = nil,
        entryCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
        self.lastUpdated = lastUpdated
        self.entryCount = entryCount
    }
}
