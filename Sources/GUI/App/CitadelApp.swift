import SwiftUI
import AppKit

@main
struct CitadelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(delegate.state)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let cowork = CoworkState()
    let sentinel = SentinelViewModel()
    let shellRouter = CitadelShellRouter()
    var menubar: MenubarController!
    var windowManager: WindowManager!
    var systemExtension: SystemExtensionManager!

    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        sentinel.bind(appState: state)
        windowManager = WindowManager(state: state, cowork: cowork, sentinel: sentinel, router: shellRouter)
        menubar = MenubarController(state: state, windows: windowManager, cowork: cowork)
        menubar.install()
        state.helper.registerDaemon()
        state.helper.connect()
        state.syncSharedRules()

        systemExtension = SystemExtensionManager(state: state)
        if ProcessInfo.processInfo.environment["CITADEL_DEMO"] == "1"
            || ProcessInfo.processInfo.environment["CITADEL_SENTINEL_DEMO"] == "1" {
            sentinel.loadDemo()
            state.loadDemoData()
        } else {
            systemExtension.activate()
            sentinel.startEngine()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.windowManager.showMainWindow()
            CitadelDeskCompanionController.shared.onRequestMainWindow = { [weak self] in
                self?.windowManager.showMainWindow()
            }
            CitadelDeskCompanionController.shared.presentIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowManager.showMainWindow()
        return true
    }
}
