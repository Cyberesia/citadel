import SwiftUI

/// Sub-modes inside the Sentinel section (mirrors Monitor: Activity / Rules / Settings).
public enum SentinelShellMode: String, CaseIterable, Identifiable, Sendable {
    case activity
    case rules
    case settings

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .activity: return L10n.sentinelActivity
        case .rules: return L10n.sentinelRules
        case .settings: return L10n.sentinelSettings
        }
    }

    public var systemImage: String {
        switch self {
        case .activity: return "radar"
        case .rules: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
