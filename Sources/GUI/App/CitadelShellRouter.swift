import Foundation
import Combine

/// Shared navigation state for the main Citadel window (menubar, popover, shell).
@MainActor
final class CitadelShellRouter: ObservableObject {
    @Published var section: CitadelNavSection = .sentinel
    @Published var sentinelMode: SentinelShellMode = .activity
    @Published var coworkMode: CoworkShellMode = .home

    func showActivity() {
        section = .sentinel
        sentinelMode = .activity
    }

    func showRules() {
        section = .sentinel
        sentinelMode = .rules
    }

    func showSettings() {
        section = .sentinel
        sentinelMode = .settings
    }

    func showCowork() {
        section = .cowork
    }
}
