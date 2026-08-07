import AppKit
import SwiftUI

/// AppKit overlay that captures scroll-wheel zoom, trackpad pinch, and
/// click-drag panning, reporting them back to SwiftUI. Doing all input in one
/// NSView avoids the flakiness of mixing SwiftUI gestures with AppKit events.
struct ScrollWheelZoomView: NSViewRepresentable {
    var onZoom: (CGFloat, CGPoint) -> Void
    var onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> MapInputView {
        let view = MapInputView()
        view.onZoom = onZoom
        view.onPan = onPan
        return view
    }

    func updateNSView(_ nsView: MapInputView, context: Context) {
        nsView.onZoom = onZoom
        nsView.onPan = onPan
    }
}

final class MapInputView: NSView {
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onPan: ((CGSize) -> Void)?

    private var lastMouse: NSPoint = .zero

    /// Match SwiftUI's coordinate system (Y=0 at top).
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            delta = 1 - event.scrollingDeltaY * 0.008
        } else {
            delta = event.deltaY > 0 ? 0.88 : 1.12
        }
        onZoom?(delta, convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + event.magnification, convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        lastMouse = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        let cur = event.locationInWindow
        let dx = cur.x - lastMouse.x
        let dy = cur.y - lastMouse.y     // window Y is up; flip for our top-down map
        lastMouse = cur
        onPan?(CGSize(width: dx, height: -dy))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
    }
}
