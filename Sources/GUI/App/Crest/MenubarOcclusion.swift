import AppKit

/// Detects when the Citadel status item crowds the notch / menu bar, and
/// provides Crest hotspot geometry.
///
/// Notch geometry uses `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` — the
/// APIs Apple actually populates on notched MacBooks. `safeAreaInsets.left/right`
/// are typically 0, so they must not be required for detection.
enum MenubarOcclusion {
    /// Preferred expanded tray width (rates + mini sparkline).
    static let expandedLength: CGFloat = 48
    /// Legacy compact width (unused when we fully hide under pressure).
    static let compactLength: CGFloat = NSStatusItem.squareLength
    /// Keep this much free space between the notch’s right edge and our item.
    static let notchClearance: CGFloat = 56

    struct Report: Equatable {
        /// True when the status item is hidden, clipped, or near/under the notch.
        var isOccluded: Bool
        var hasNotch: Bool
        /// Always prefer keeping Crest reachable on notched displays.
        var crestAlwaysAvailable: Bool
        var hotspotScreenRect: CGRect
        var reason: Reason
        /// Expanding back to rates would put the item under/near the notch.
        var expandedWouldCollide: Bool

        /// Crest hotspot should accept hover.
        var crestArmed: Bool { crestAlwaysAvailable || isOccluded }

        /// Hide the status item so it cannot shove neighbors under the notch.
        var shouldCollapseTray: Bool {
            switch reason {
            case .underNotch, .atRiskNearNotch, .menuBarOverflow, .missingButton:
                return true
            case .visible:
                return expandedWouldCollide
            }
        }

        enum Reason: Equatable {
            case visible
            case underNotch
            case atRiskNearNotch
            case menuBarOverflow
            case missingButton
        }
    }

    static func evaluate(
        statusItem: NSStatusItem,
        on screen: NSScreen? = nil,
        assumingExpandedWidth: CGFloat = expandedLength
    ) -> Report {
        let resolvedScreen = screen
            ?? statusItem.button?.window?.screen
            ?? NSScreen.main

        guard let resolvedScreen else {
            return Report(
                isOccluded: true,
                hasNotch: false,
                crestAlwaysAvailable: false,
                hotspotScreenRect: fallbackHotspot(in: NSScreen.screens.first?.frame ?? .zero),
                reason: .missingButton,
                expandedWouldCollide: true
            )
        }

        let hotspot = hotspotRect(on: resolvedScreen)
        let notched = hasNotch(on: resolvedScreen)
        let always = notched

        guard let button = statusItem.button, let window = button.window else {
            return Report(
                isOccluded: true,
                hasNotch: notched,
                crestAlwaysAvailable: always,
                hotspotScreenRect: hotspot,
                reason: .missingButton,
                expandedWouldCollide: true
            )
        }

        // Hidden on purpose (Crest mode) or by the system — treat as occluded.
        // Without a frame we keep collapse armed; MenubarController probes periodically.
        if !statusItem.isVisible {
            return Report(
                isOccluded: true,
                hasNotch: notched,
                crestAlwaysAvailable: always,
                hotspotScreenRect: hotspot,
                reason: notched ? .atRiskNearNotch : .menuBarOverflow,
                expandedWouldCollide: true
            )
        }

        let frame = window.frame
        if frame.width < 4 || frame.height < 4 {
            return Report(
                isOccluded: true,
                hasNotch: notched,
                crestAlwaysAvailable: always,
                hotspotScreenRect: hotspot,
                reason: .menuBarOverflow,
                expandedWouldCollide: true
            )
        }

        let expandedProbe = CGRect(
            x: frame.maxX - assumingExpandedWidth,
            y: frame.minY,
            width: assumingExpandedWidth,
            height: max(frame.height, 22)
        )
        let expandedWouldCollide = crowdsNotch(expandedProbe, on: resolvedScreen)
            || wouldCollideWithAppMenus(expandedProbe, on: resolvedScreen)

        if let pressure = notchPressure(for: frame, on: resolvedScreen) {
            return Report(
                isOccluded: true,
                hasNotch: true,
                crestAlwaysAvailable: true,
                hotspotScreenRect: hotspot,
                reason: pressure,
                expandedWouldCollide: true
            )
        }

        let menuReserve = resolvedScreen.frame.width * 0.38
        let appMenuRightEdge = resolvedScreen.frame.minX + menuReserve
        if frame.midX < appMenuRightEdge {
            return Report(
                isOccluded: true,
                hasNotch: notched,
                crestAlwaysAvailable: always,
                hotspotScreenRect: hotspot,
                reason: .menuBarOverflow,
                expandedWouldCollide: true
            )
        }

        return Report(
            isOccluded: false,
            hasNotch: notched,
            crestAlwaysAvailable: always,
            hotspotScreenRect: hotspot,
            reason: .visible,
            expandedWouldCollide: expandedWouldCollide
        )
    }

    // MARK: - Geometry

    static func hasNotch(on screen: NSScreen) -> Bool {
        if screen.safeAreaInsets.top > 0 { return true }
        if screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil {
            return true
        }
        return false
    }

    /// Menu-bar region reserved for status items (right of the notch).
    static func statusItemZone(on screen: NSScreen) -> CGRect? {
        screen.auxiliaryTopRightArea
    }

    static func hotspotRect(on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let height: CGFloat = 16
        if let notch = notchRect(on: screen) {
            let width = max(notch.width + 64, 240)
            return CGRect(
                x: notch.midX - width / 2,
                y: frame.maxY - height,
                width: width,
                height: height
            )
        }
        let width: CGFloat = 240
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    static func notchRect(on screen: NSScreen) -> CGRect? {
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            guard width > 20 else { return nil }
            let height = max(screen.safeAreaInsets.top, left.height, right.height, 32)
            return CGRect(
                x: left.maxX,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
        }

        // Legacy fallback — some environments still expose left/right safe-area insets.
        let inset = screen.safeAreaInsets
        guard inset.top > 0, inset.left > 0, inset.right > 0 else { return nil }
        let inferred = screen.frame.width - inset.left - inset.right
        guard inferred > 80, inferred < 280 else { return nil }
        return CGRect(
            x: screen.frame.minX + inset.left,
            y: screen.frame.maxY - max(inset.top, 32),
            width: inferred,
            height: max(inset.top, 32)
        )
    }

    /// `.underNotch` / `.atRiskNearNotch` when the item sits on or near the camera.
    private static func notchPressure(for frame: CGRect, on screen: NSScreen) -> Report.Reason? {
        if let zone = statusItemZone(on: screen) {
            // Extends into the notch (left of the status-item safe zone).
            if frame.minX < zone.minX - 0.5 {
                return .underNotch
            }
            // Occupying the notch shoulder — this is what shoves neighbors under.
            if frame.minX < zone.minX + notchClearance {
                return .atRiskNearNotch
            }
            return nil
        }

        guard let notch = notchRect(on: screen) else { return nil }
        let danger = notch.insetBy(dx: -notchClearance, dy: -4)
        if frame.intersects(danger) {
            return .underNotch
        }
        if frame.minX < notch.maxX + notchClearance, frame.maxX > notch.minX - 8 {
            return .atRiskNearNotch
        }
        return nil
    }

    private static func crowdsNotch(_ rect: CGRect, on screen: NSScreen) -> Bool {
        notchPressure(for: rect, on: screen) != nil
    }

    private static func wouldCollideWithAppMenus(_ rect: CGRect, on screen: NSScreen) -> Bool {
        let menuReserve = screen.frame.width * 0.38
        return rect.midX < screen.frame.minX + menuReserve
    }

    private static func fallbackHotspot(in frame: CGRect) -> CGRect {
        CGRect(x: frame.midX - 120, y: frame.maxY - 16, width: 240, height: 16)
    }
}
