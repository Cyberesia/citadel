import Foundation

public enum RuleAction: String, Codable, CaseIterable, Sendable {
    case allow, deny, ask
}

public enum RuleDirection: String, Codable, CaseIterable, Sendable {
    case outgoing, incoming, any
}

public enum RuleScope: String, Codable, CaseIterable, Sendable {
    case process, domain, ip, port, any
}

public enum AppMode: String, Codable, CaseIterable, Sendable {
    case alert, silentAllow, silentDeny
}
