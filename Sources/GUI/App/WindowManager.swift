import AppKit
import SwiftUI
import Combine

@MainActor
final class WindowManager {
    private let state: AppState
    private let cowork: CoworkState
    private let fortress: FortressViewModel
    let router: CitadelShellRouter
    private weak var mainWindow: NSWindow?
    private var alertWindow: NSWindow?
    private var alertCancellable: AnyCancellable?

    init(state: AppState, cowork: CoworkState, fortress: FortressViewModel, router: CitadelShellRouter) {
        self.state = state
        self.cowork = cowork
        self.fortress = fortress
        self.router = router
        observeAlerts()
    }

    // MARK: - Public windows

    func showMainWindow() {
        // Menu-bar (.accessory) apps hide windows when mic/Speech TCC steals focus.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if let existing = mainWindow ?? findMainWindow() {
            mainWindow = existing
            focus(existing)
            return
        }
        mainWindow = makeWindow(
            title: "Citadel",
            defaultSize: NSSize(width: 1180, height: 740),
            minSize: NSSize(width: 1000, height: 640),
            autosaveName: "Citadel.Main",
            content: CitadelShellView()
                .environmentObject(state)
                .environmentObject(cowork)
                .environmentObject(fortress)
                .environmentObject(router)
        )
    }

    func showNetworkMonitor() {
        router.showActivity()
        showMainWindow()
    }

    func showRulesManager() {
        router.showRules()
        showMainWindow()
    }

    func showSettings() {
        router.showSettings()
        showMainWindow()
    }

    func showCowork() {
        router.showCowork()
        showMainWindow()
    }

    // MARK: - Window factory

    private func makeWindow<Content: View>(
        title: String,
        defaultSize: NSSize,
        minSize: NSSize,
        autosaveName: String,
        content: Content,
        resizable: Bool = true
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: content)
        window.setContentSize(defaultSize)
        window.setFrameAutosaveName(autosaveName)
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }

        focus(window)
        return window
    }

    private func focus(_ window: NSWindow) {
        window.hidesOnDeactivate = false
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first { $0.frameAutosaveName == "Citadel.Main" }
    }

    // MARK: - Connection alerts (single path via AppState)

    private func observeAlerts() {
        alertCancellable = state.$pendingAlerts
            .receive(on: RunLoop.main)
            .sink { [weak self] alerts in
                self?.syncAlertWindow(hasAlert: !alerts.isEmpty)
            }
    }

    private func syncAlertWindow(hasAlert: Bool) {
        if hasAlert {
            if alertWindow == nil { presentAlertWindow() }
        } else {
            alertWindow?.close()
            alertWindow = nil
        }
    }

    private func presentAlertWindow() {
        let hosting = NSHostingController(
            rootView: AlertWindowContent().environmentObject(state)
        )
        let window = NSPanel(contentViewController: hosting)
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        alertWindow = window
    }
}
