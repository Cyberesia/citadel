import Foundation
import Combine

/// Shared navigation state for the main Citadel window (menubar, popover, shell).
@MainActor
final class CitadelShellRouter: ObservableObject {
    @Published var section: CitadelNavSection = .fortress
    @Published var fortressMode: FortressShellMode = .activity
    @Published var coworkMode: CoworkShellMode = .home

    func showActivity() {
        section = .fortress
        fortressMode = .activity
    }

    func showRules() {
        section = .fortress
        fortressMode = .rules
    }

    func showSettings() {
        section = .fortress
        fortressMode = .settings
    }

    func showCowork() {
        section = .cowork
    }
}
