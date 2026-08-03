import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+).
enum LoginItemHelper {
    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // Best-effort; Settings still persists the preference.
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
