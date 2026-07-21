import AppKit
import SwiftUI

/// Floating Desk Companion — Citadel's ambient agent mascot (not a "pet").
@MainActor
final class CitadelDeskCompanionController: ObservableObject {
    static let shared = CitadelDeskCompanionController()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "citadel.companion.enabled") }
    }
    @Published var quietMode: Bool {
        didSet { UserDefaults.standard.set(quietMode, forKey: "citadel.companion.dnd") }
    }
    @Published var mood: CompanionMood = .idle
    @Published var isStreaming = false

    private var panel: NSPanel?
    /// Wired at launch — restores Citadel even when minimized or hidden.
    var onRequestMainWindow: (() -> Void)?

    enum CompanionMood: String {
        case idle, thinking, happy, confirm
    }

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "citadel.companion.enabled") as? Bool ?? true
        quietMode = UserDefaults.standard.bool(forKey: "citadel.companion.dnd")
    }

    func syncStreaming(_ streaming: Bool) {
        isStreaming = streaming
        mood = streaming ? .thinking : .idle
    }

    func showConfirmPulse() {
        guard !quietMode else { return }
        mood = .confirm
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.mood == .confirm else { return }
            self.mood = self.isStreaming ? .thinking : .idle
        }
    }

    func presentIfNeeded() {
        guard isEnabled else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil {
            let content = NSHostingView(rootView: CitadelDeskCompanionView().environmentObject(self))
            let size: CGFloat = 112
            content.frame = CGRect(x: 0, y: 0, width: size, height: size)
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor

            let panel = NSPanel(
                contentRect: CGRect(x: 120, y: 120, width: size, height: size),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hasShadow = false
            panel.contentView = content
            panel.isMovableByWindowBackground = true
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Click-through: bring the main Citadel window forward (including from minimized).
    func activateMainWindow() {
        if let onRequestMainWindow {
            onRequestMainWindow()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if let main = NSApp.windows.first(where: { $0.frameAutosaveName == "Citadel.Main" }) {
                if main.isMiniaturized { main.deminiaturize(nil) }
                main.makeKeyAndOrderFront(nil)
            }
        }
        if mood == .confirm {
            mood = isStreaming ? .thinking : .idle
        }
    }
}

struct CitadelDeskCompanionView: View {
    @EnvironmentObject var controller: CitadelDeskCompanionController
    @State private var bob = false

    /// Prism accent — coral/orange from the Citadel mark (not violet).
    private let accent = Color(red: 1.0, green: 0.44, blue: 0.26)

    var body: some View {
        // Soft glow via shadow only — no filled circle (avoids opaque haze / square clip).
        Image("CitadelMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 96, height: 96)
            .shadow(color: accent.opacity(glowOpacity), radius: 16, y: 0)
            .shadow(color: accent.opacity(glowOpacity * 0.55), radius: 28, y: 0)
            .offset(y: bob ? -2 : 2)
            .animation(
                controller.mood == .thinking
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                value: bob
            )
            .scaleEffect(controller.mood == .confirm ? 1.06 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.mood)
            .frame(width: 112, height: 112)
            .contentShape(Rectangle())
            .onTapGesture { controller.activateMainWindow() }
            .onAppear { bob = true }
            .help(L10n.deskCompanion)
    }

    private var glowOpacity: Double {
        switch controller.mood {
        case .idle: return 0.35
        case .thinking: return 0.55
        case .happy: return 0.45
        case .confirm: return 0.65
        }
    }
}
