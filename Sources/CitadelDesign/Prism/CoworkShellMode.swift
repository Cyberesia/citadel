import SwiftUI

/// Keep sub-navigation (expand when the Keep navbar group is active).
public enum CoworkShellMode: String, CaseIterable, Identifiable, Sendable {
    case home
    case sessions
    case teams
    case assistants
    case tools
    case schedule
    case agents

    public var id: String { rawValue }

    /// First-run friendly strip — everything else lives under More.
    public static var primaryCases: [CoworkShellMode] { [.home, .sessions, .assistants] }
    public static var advancedCases: [CoworkShellMode] { [.teams, .tools, .schedule, .agents] }

    public var label: String {
        switch self {
        case .home: return L10n.keepAsk
        case .sessions: return L10n.coworkSessions
        case .teams: return L10n.coworkTeams
        case .assistants: return L10n.coworkAssistants
        case .tools: return L10n.coworkTools
        case .schedule: return L10n.coworkSchedule
        case .agents: return L10n.coworkAgents
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "text.bubble.fill"
        case .sessions: return "bubble.left.and.bubble.right.fill"
        case .teams: return "person.3.fill"
        case .assistants: return "person.2.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .schedule: return "calendar.badge.clock"
        case .agents: return "cpu.fill"
        }
    }

    public var isAdvanced: Bool { Self.advancedCases.contains(self) }
}
