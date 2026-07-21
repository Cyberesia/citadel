import Foundation

/// Role of a process within an app family (main vs helper/sub-process).
public enum ProcessRole: String, Codable, CaseIterable, Sendable, Hashable {
    case main
    case helper
    case renderer
    case gpu
    case network
    case agent
    case unknown

    public var label: String {
        switch self {
        case .main: return L10n.roleMain
        case .helper: return L10n.roleHelpers
        case .renderer: return L10n.roleRenderer
        case .gpu: return L10n.roleGPU
        case .network: return L10n.roleNetwork
        case .agent: return L10n.roleAgent
        case .unknown: return L10n.roleOther
        }
    }

    public var systemImage: String {
        switch self {
        case .main: return "app.fill"
        case .helper: return "puzzlepiece.extension"
        case .renderer: return "paintbrush"
        case .gpu: return "cpu"
        case .network: return "network"
        case .agent: return "sparkles"
        case .unknown: return "questionmark.circle"
        }
    }
}
