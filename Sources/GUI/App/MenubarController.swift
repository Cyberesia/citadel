import AppKit
import SwiftUI
import Combine

@MainActor
final class MenubarController: NSObject {
    private let state: AppState
    private let windows: WindowManager
    private let cowork: CoworkState?
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var trafficCancellable: AnyCancellable?
    private var crest: CrestController!
    private var crestPopoverAnchor: NSPanel?
    /// When true, the rates tray is hidden — Crest (notch hover) is the recover UI.
    private var trayCollapsed = false
    private var clearPolls = 0
    private var screenObserver: NSObjectProtocol?

    init(state: AppState, windows: WindowManager, cowork: CoworkState? = nil) {
        self.state = state
        self.windows = windows
        self.cowork = cowork
        super.init()
    }

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: MenubarOcclusion.expandedLength)
        statusItem.autosaveName = "citadel.menubar.status"
        // We hide ourselves under notch pressure (Crest recovers). Keep removalAllowed
        // as a safety net if detection races the first layout.
        statusItem.behavior = [.removalAllowed]
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let popoverView = MenubarPopoverView(close: { [weak self] in self?.popover.performClose(nil) })
            .environmentObject(state)
            .environmentObject(windows)
            .frame(width: 380, height: 540)
        popover.contentViewController = NSHostingController(rootView: popoverView)

        crest = CrestController(state: state, windows: windows, cowork: cowork)
        crest.attach(
            statusItem: statusItem,
            onOpenMenubarPopover: { [weak self] in self?.revealPopoverFromCrest() },
            onTrayPressure: { [weak self] report in self?.applyTrayPressure(report) }
        )

        render()

        trafficCancellable = state.$trafficHistory
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }

        // Re-check tray only when display layout changes — never flash the icon on a timer.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconsiderTrayAfterScreenChange() }
        }

        NotificationCenter.default.addObserver(
            forName: .citadelLocaleDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPopoverRoot() }
        }
    }

    private func refreshPopoverRoot() {
        let popoverView = MenubarPopoverView(close: { [weak self] in self?.popover.performClose(nil) })
            .environmentObject(state)
            .environmentObject(windows)
            .frame(width: 380, height: 540)
        popover.contentViewController = NSHostingController(rootView: popoverView)
    }

    /// One-shot re-show after display changes; Crest will collapse again if still crowded.
    private func reconsiderTrayAfterScreenChange() {
        guard trayCollapsed else { return }
        clearPolls = 0
        statusItem.length = MenubarOcclusion.expandedLength
        statusItem.isVisible = true
        render()
    }

    /// Hide immediately when near the notch; only show rates after sustained clear space.
    private func applyTrayPressure(_ report: MenubarOcclusion.Report) {
        if report.shouldCollapseTray {
            clearPolls = 0
            setTrayCollapsed(true)
            return
        }
        // Hidden items can't prove clear space — stay in Crest until a screen-change probe.
        guard statusItem.isVisible else { return }
        clearPolls += 1
        if clearPolls >= 5 {
            setTrayCollapsed(false)
        }
    }

    private func setTrayCollapsed(_ collapsed: Bool) {
        guard trayCollapsed != collapsed else {
            if collapsed, statusItem.isVisible {
                statusItem.isVisible = false
            }
            return
        }
        trayCollapsed = collapsed
        if collapsed {
            statusItem.isVisible = false
            statusItem.length = MenubarOcclusion.expandedLength
        } else {
            statusItem.length = MenubarOcclusion.expandedLength
            statusItem.isVisible = true
        }
        render()
    }

    /// Open the full menubar popover even when the status item is under the notch.
    private func revealPopoverFromCrest() {
        NSApp.activate(ignoringOtherApps: true)
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        let report = MenubarOcclusion.evaluate(statusItem: statusItem)
        if !report.isOccluded, let button = statusItem.button, statusItem.isVisible {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            return
        }

        // Anchor under the Crest hotspot so the tray UI still appears.
        let hot = report.hotspotScreenRect
        let anchor = NSPanel(
            contentRect: hot,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.hasShadow = false
        anchor.level = .statusBar
        anchor.ignoresMouseEvents = true
        anchor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: hot.size))
        anchor.contentView = view
        anchor.setFrame(hot, display: true)
        anchor.orderFrontRegardless()
        crestPopoverAnchor = anchor
        popover.delegate = self
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    @objc private func handleClick(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(makeItem("\(L10n.fortressActivity)…", #selector(openMonitor), keyEq: "n"))
        menu.addItem(makeItem("\(L10n.fortressRules)…", #selector(openRules), keyEq: "r"))
        menu.addItem(makeItem("\(L10n.fortressSettings)…", #selector(openSettings), keyEq: ","))
        menu.addItem(.separator())
        if let cowork {
            let agentTitle: String
            switch cowork.coreStatus {
            case .running:
                agentTitle = cowork.isStreaming ? "\(L10n.keep) · agent working…" : "\(L10n.keep) · agent ready"
            case .starting:
                agentTitle = "\(L10n.keep) · starting…"
            case .failed:
                agentTitle = "\(L10n.keep) · agent error"
            case .stopped:
                agentTitle = "\(L10n.keep) · agent off"
            }
            let statusLine = NSMenuItem(title: agentTitle, action: nil, keyEquivalent: "")
            statusLine.isEnabled = false
            menu.addItem(statusLine)
            menu.addItem(makeItem(L10n.openKeep, #selector(openCowork), keyEq: "k"))
            menu.addItem(.separator())
        }
        let modeMenu = NSMenu(title: L10n.mode)
        modeMenu.addItem(makeItem(L10n.alertMode, #selector(modeAlert), keyEq: "", state: state.mode == .alert ? .on : .off))
        modeMenu.addItem(makeItem(L10n.silentAllow, #selector(modeAllow), keyEq: "", state: state.mode == .silentAllow ? .on : .off))
        modeMenu.addItem(makeItem(L10n.silentDeny, #selector(modeDeny), keyEq: "", state: state.mode == .silentDeny ? .on : .off))
        let modeItem = NSMenuItem(title: L10n.mode, action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.quitCitadel, #selector(quit), keyEq: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeItem(_ title: String, _ sel: Selector, keyEq: String, state: NSControl.StateValue = .off) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: keyEq)
        item.target = self
        item.state = state
        return item
    }

    @objc private func openMonitor() { windows.showNetworkMonitor() }
    @objc private func openCowork() { windows.showCowork() }
    @objc private func openRules() { windows.showRulesManager() }
    @objc private func openSettings() { windows.showSettings() }
    @objc private func modeAlert() { state.setMode(.alert) }
    @objc private func modeAllow() { state.setMode(.silentAllow) }
    @objc private func modeDeny() { state.setMode(.silentDeny) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func render() {
        guard let button = statusItem.button else { return }
        button.image = makeStatusImage()
        button.imagePosition = .imageOnly
        let rates = "↓ \(CitadelFormat.bytesPerSec(state.currentIn))  ↑ \(CitadelFormat.bytesPerSec(state.currentOut))"
        button.toolTip = trayCollapsed
            ? "Citadel · tray hidden (notch). \(rates) · Hover the notch for Crest"
            : rates
    }

    private func makeStatusImage() -> NSImage {
        let history = Array(state.trafficHistory.suffix(20))
        let inSpeed = state.currentIn
        let outSpeed = state.currentOut
        let inText = compactSpeed(inSpeed)
        let outText = compactSpeed(outSpeed)
        let size = NSSize(width: 46, height: 22)
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
        let inStr = NSAttributedString(string: inText, attributes: attrs.merging([.foregroundColor: NSColor(red: 1.0, green: 0.44, blue: 0.26, alpha: 1)]) { _, b in b })
        let outStr = NSAttributedString(string: outText, attributes: attrs.merging([.foregroundColor: NSColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1)]) { _, b in b })
        inStr.draw(at: NSPoint(x: 1, y: 11))
        outStr.draw(at: NSPoint(x: 1, y: 1))

        let barAreaX: CGFloat = 28
        let barAreaW: CGFloat = 16
        let barCount = min(5, max(history.count, 1))
        let barW: CGFloat = (barAreaW - CGFloat(barCount - 1) * 1.0) / CGFloat(barCount)
        let maxIn: CGFloat = max(1, CGFloat(history.map { $0.bytesIn }.max() ?? 1))
        let maxOut: CGFloat = max(1, CGFloat(history.map { $0.bytesOut }.max() ?? 1))
        for i in 0..<barCount {
            guard i < history.count else { break }
            let h = history[history.count - barCount + i]
            let x = barAreaX + CGFloat(i) * (barW + 1)
            let topH = min(10, CGFloat(h.bytesIn) / maxIn * 10)
            let botH = min(10, CGFloat(h.bytesOut) / maxOut * 10)
            NSColor(red: 1.0, green: 0.44, blue: 0.26, alpha: 0.95).setFill()
            NSBezierPath(rect: NSRect(x: x, y: 11, width: barW, height: max(1, topH))).fill()
            NSColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 0.95).setFill()
            NSBezierPath(rect: NSRect(x: x, y: 11 - max(1, botH), width: barW, height: max(1, botH))).fill()
        }
        img.isTemplate = false
        return img
    }

    private func compactSpeed(_ n: Int64) -> String {
        let b = Double(n)
        if b < 1024 { return "\(Int(b))B" }
        if b < 1024 * 1024 { return String(format: "%.0fK", b/1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1fM", b/1024/1024) }
        return String(format: "%.1fG", b/1024/1024/1024)
    }
}

extension MenubarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        crestPopoverAnchor?.orderOut(nil)
        crestPopoverAnchor = nil
    }
}

extension WindowManager: ObservableObject {}
