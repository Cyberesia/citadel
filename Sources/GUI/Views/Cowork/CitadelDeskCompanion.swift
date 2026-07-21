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
            let size: CGFloat = 88
            content.frame = CGRect(x: 0, y: 0, width: size, height: size)

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

    /// Diagonal pair, centroid centered in the 88pt badge.
    private static let marks: [(size: CGFloat, x: CGFloat, y: CGFloat)] = [
        (30, -10, 10),  // large — lower-left
        (20, 14, -14),  // medium — upper-right
    ]

    private let markGradient = LinearGradient(
        colors: [
            Color(red: 0.65, green: 0.45, blue: 1.0),
            Color(red: 0.35, green: 0.72, blue: 0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.55, green: 0.38, blue: 1.0).opacity(glowOpacity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 40
                    )
                )

            ZStack {
                ForEach(Array(Self.marks.enumerated()), id: \.offset) { _, mark in
                    aisanceMark(size: mark.size)
                        .offset(x: mark.x, y: mark.y)
                }
            }
            .offset(y: bob ? -2 : 2)
            .animation(
                controller.mood == .thinking
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                value: bob
            )
            .scaleEffect(controller.mood == .confirm ? 1.06 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.mood)
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
        .onTapGesture { controller.activateMainWindow() }
        .onAppear { bob = true }
        .help(L10n.deskCompanion)
    }

    private func aisanceMark(size: CGFloat) -> some View {
        Image("AisanceMark")
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(markGradient)
    }

    private var glowOpacity: Double {
        switch controller.mood {
        case .idle: return 0.32
        case .thinking: return 0.48
        case .happy: return 0.40
        case .confirm: return 0.55
        }
    }
}
