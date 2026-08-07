import AppKit
import SwiftUI

@MainActor
final class CitadelUpdateController: ObservableObject {
    static let shared = CitadelUpdateController()

    @Published private(set) var latestRelease: CitadelGitHubRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?
    @Published private(set) var updateAvailable = false

    private let lastCheckKey = "citadel.update.lastCheck"
    private let dismissedVersionKey = "citadel.update.dismissedVersion"
    private let checkInterval: TimeInterval = 86_400

    private init() {}

    var statusText: String {
        if isChecking { return L10n.updateChecking }
        if updateAvailable, let release = latestRelease {
            return L10n.updateAvailable(release.version)
        }
        if let lastError, !lastError.isEmpty { return lastError }
        return L10n.updateUpToDate
    }

    func checkIfNeeded() async {
        if isChecking { return }
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < checkInterval,
           latestRelease != nil {
            refreshAvailability()
            return
        }
        await check(force: false)
    }

    func check(force: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        defer { isChecking = false }

        do {
            let release = try await CitadelGitHubReleaseAPI.fetchLatest()
            latestRelease = release
            refreshAvailability()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            if updateAvailable {
                maybePresentUpdateAlert(for: release)
            }
        } catch {
            lastError = error.localizedDescription
            if force || latestRelease == nil {
                updateAvailable = false
            }
        }
    }

    func openDownloadPage() {
        guard let url = latestRelease?.preferredDownloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissCurrentUpdate() {
        guard let version = latestRelease?.version else { return }
        UserDefaults.standard.set(version, forKey: dismissedVersionKey)
    }

    private func refreshAvailability() {
        guard let release = latestRelease else {
            updateAvailable = false
            return
        }
        updateAvailable = CitadelVersionCompare.isRemoteNewer(
            remote: release.version,
            local: AppConstants.version
        )
    }

    private func maybePresentUpdateAlert(for release: CitadelGitHubRelease) {
        let dismissed = UserDefaults.standard.string(forKey: dismissedVersionKey)
        guard release.version != dismissed else { return }

        let alert = NSAlert()
        alert.messageText = L10n.updateAlertTitle
        alert.informativeText = L10n.updateAlertBody(release.version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.downloadUpdate)
        alert.addButton(withTitle: L10n.updateLater)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openDownloadPage()
        } else {
            dismissCurrentUpdate()
        }
    }
}
