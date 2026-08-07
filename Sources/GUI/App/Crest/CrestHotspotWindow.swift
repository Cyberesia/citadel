import AppKit
import SwiftUI

/// Borderless top-edge strip — always hittable when Crest is armed.
@MainActor
final class CrestHotspotWindow: NSPanel {
    private var tracking: NSTrackingArea?
    private let chromeHost: NSHostingView<CrestHotspotChrome>
    var onHoverChanged: ((Bool) -> Void)?

    init() {
        chromeHost = NSHostingView(rootView: CrestHotspotChrome(emphasis: .off))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 16),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        alphaValue = 0

        chromeHost.frame = contentView?.bounds ?? .zero
        chromeHost.autoresizingMask = [.width, .height]
        contentView = chromeHost
        updateTracking()
    }

    func relocate(to screenRect: CGRect) {
        guard frame != screenRect else { return }
        setFrame(screenRect, display: true)
        updateTracking()
    }

    func setArmed(_ armed: Bool, emphasized: Bool) {
        let emphasis: CrestHotspotChrome.Emphasis
        if !armed {
            emphasis = .off
        } else if emphasized {
            emphasis = .urgent
        } else {
            emphasis = .idle
        }
        let nextIgnores = !armed
        let nextAlpha: CGFloat = armed ? 1 : 0
        let needsChrome = chromeHost.rootView.emphasis != emphasis
        let needsTracking = ignoresMouseEvents != nextIgnores
        ignoresMouseEvents = nextIgnores
        alphaValue = nextAlpha
        if needsChrome {
            chromeHost.rootView = CrestHotspotChrome(emphasis: emphasis)
        }
        if needsTracking {
            updateTracking()
        }
    }

    private func updateTracking() {
        guard let contentView else { return }
        if let tracking { contentView.removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct CrestHotspotChrome: View {
    enum Emphasis {
        case off
        /// Always-on notch affordance (subtle).
        case idle
        /// Icon is under/near notch or overflowed (brighter).
        case urgent
    }

    var emphasis: Emphasis = .idle

    var body: some View {
        ZStack {
            Color.clear
            if emphasis != .off {
                Capsule()
                    .fill(PrismTheme.accent.opacity(emphasis == .urgent ? 0.75 : 0.35))
                    .frame(width: emphasis == .urgent ? 42 : 28, height: 3)
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
    }
}
