import AppKit
import SwiftUI
import Combine

/// Citadel Crest — always-on notch / top-center recover for menubar overflow.
@MainActor
final class CrestController {
    private let state: AppState
    private let windows: WindowManager
    private let cowork: CoworkState?
    private weak var statusItem: NSStatusItem?
    private var onOpenMenubarPopover: (() -> Void)?
    private var onTrayPressure: ((MenubarOcclusion.Report) -> Void)?

    private let hotspot = CrestHotspotWindow()
    private var panel: NSPanel?
    private var pollTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private var lastReport: MenubarOcclusion.Report?
    private var lastHotspotRect: CGRect = .null
    private var lastArmed = false
    private var lastEmphasized = false
    private var panelVisible = false
    private var pointerOverHotspot = false

    init(state: AppState, windows: WindowManager, cowork: CoworkState? = nil) {
        self.state = state
        self.windows = windows
        self.cowork = cowork
    }

    func attach(
        statusItem: NSStatusItem,
        onOpenMenubarPopover: @escaping () -> Void,
        onTrayPressure: @escaping (MenubarOcclusion.Report) -> Void
    ) {
        self.statusItem = statusItem
        self.onOpenMenubarPopover = onOpenMenubarPopover
        self.onTrayPressure = onTrayPressure
        hotspot.onHoverChanged = { [weak self] hovering in
            self?.handleHotspotHover(hovering)
        }
        hotspot.orderFrontRegardless()
        hotspot.setArmed(false, emphasized: false)

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOcclusion() }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
        refreshOcclusion()
    }

    func teardown() {
        pollTimer?.invalidate()
        pollTimer = nil
        hidePanel(animated: false)
        hotspot.orderOut(nil)
    }

    // MARK: - Occlusion

    private func refreshOcclusion() {
        guard let statusItem else { return }
        let report = MenubarOcclusion.evaluate(statusItem: statusItem)
        lastReport = report

        let rect = report.hotspotScreenRect
        if lastHotspotRect.isNull || lastHotspotRect != rect {
            // Avoid thrashing tracking areas while the pointer is on the hairline.
            if !pointerOverHotspot || lastHotspotRect.isNull {
                hotspot.relocate(to: rect)
                lastHotspotRect = rect
            }
        }

        let armed = report.crestArmed
        let emphasized = report.isOccluded || report.shouldCollapseTray
        if armed != lastArmed || emphasized != lastEmphasized {
            hotspot.setArmed(armed, emphasized: emphasized)
            lastArmed = armed
            lastEmphasized = emphasized
        }
        if armed {
            hotspot.orderFrontRegardless()
        }
        onTrayPressure?(report)
    }

    // MARK: - Hover

    private func handleHotspotHover(_ hovering: Bool) {
        pointerOverHotspot = hovering
        hideWorkItem?.cancel()
        guard lastReport?.crestArmed == true else { return }
        if hovering {
            showPanel()
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.pointerOverHotspot || self.panelContainsMouse() { return }
                self.hidePanel(animated: true)
            }
            hideWorkItem = work
            // Long enough to cross the hairline → panel without flicker.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private func panelContainsMouse() -> Bool {
        guard let panel, panel.isVisible else { return false }
        // Inflate slightly so the gap under the notch doesn't drop hover.
        return panel.frame.insetBy(dx: -8, dy: -10).contains(NSEvent.mouseLocation)
    }

    // MARK: - Panel

    private func showPanel() {
        guard let report = lastReport, report.crestArmed else { return }

        // Already up — keep it; don't restart the fade (that was the blink).
        if panelVisible, let panel, panel.isVisible {
            hideWorkItem?.cancel()
            panel.orderFrontRegardless()
            return
        }

        let root = CrestPanelView(
            state: state,
            windows: windows,
            cowork: cowork,
            reason: report.reason,
            hasNotch: report.hasNotch,
            onOpenCitadel: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.windows.showMainWindow()
            },
            onOpenMenubar: { [weak self] in
                self?.hidePanel(animated: false)
                self?.onOpenMenubarPopover?()
            },
            onDismiss: { [weak self] in self?.hidePanel(animated: true) }
        )
        .onHover { [weak self] inside in
            if inside {
                self?.hideWorkItem?.cancel()
            } else {
                self?.handleHotspotHover(false)
            }
        }

        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 360, height: 220)

        if panel == nil {
            let p = NSPanel(
                contentRect: hosting.view.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isExcludedFromWindowsMenu = true
            panel = p
        }

        guard let panel else { return }
        panel.contentViewController = hosting
        panel.setContentSize(hosting.view.fittingSize)

        let hotspotFrame = report.hotspotScreenRect
        let size = panel.frame.size
        let x = hotspotFrame.midX - size.width / 2
        // Overlap the hairline slightly so mouseEntered/Exited don't flap in the gap.
        let y = hotspotFrame.minY - size.height + 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panelVisible = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel(animated: Bool) {
        guard let panel, panelVisible else { return }
        panelVisible = false
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
    }
}
