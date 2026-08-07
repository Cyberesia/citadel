import SwiftUI

/// Sub-modes inside the Fortress section.
public enum FortressShellMode: String, CaseIterable, Identifiable, Sendable {
    case activity
    case suspects
    case history
    case rules
    case settings

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .activity: return L10n.fortressActivity
        case .suspects: return L10n.fortressSuspects
        case .history: return L10n.fortressHistory
        case .rules: return L10n.fortressRules
        case .settings: return L10n.fortressSettings
        }
    }

    public var systemImage: String {
        switch self {
        case .activity: return "radar"
        case .suspects: return "exclamationmark.shield.fill"
        case .history: return "clock.arrow.circlepath"
        case .rules: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
