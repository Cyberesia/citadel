import AppKit

/// Keeps Citadel's main window alive around dictation / TCC prompts.
///
/// Citadel runs as `.accessory` (menu-bar app). Mic / Speech permission sheets steal
/// activation and macOS often hides accessory windows — which looked like "mic closes the app".
@MainActor
enum CitadelMainWindowPresenter {
    static func restoreFocus() {
        promoteForDictation()
    }

    /// Promote to regular activation + order the main window front. Safe to call often.
    static func promoteForDictation() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        CitadelDeskCompanionController.shared.activateMainWindow()
        if let main = NSApp.windows.first(where: { $0.frameAutosaveName == "Citadel.Main" }) {
            main.hidesOnDeactivate = false
            if main.isMiniaturized { main.deminiaturize(nil) }
            main.makeKeyAndOrderFront(nil)
        }
    }

    /// TCC dialogs dismiss asynchronously — one deferred pass only (no multi-bounce thrash).
    static func restoreFocusAfterPermissionPrompt() {
        promoteForDictation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            promoteForDictation()
        }
    }
}
