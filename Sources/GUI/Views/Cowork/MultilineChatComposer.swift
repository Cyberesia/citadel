import AppKit
import SwiftUI

/// macOS chat input: **Return** sends, **Shift+Return** inserts newline.
struct MultilineChatComposer: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var isEnabled: Bool
    var colorScheme: ColorScheme
    var caretColor: NSColor = .prismAccentCaret
    var selectionColor: NSColor = NSColor.labelColor.withAlphaComponent(0.18)
    var focusRequest: Int = 0
    var onFocusChange: (Bool) -> Void = { _ in }
    var onDropFileURLs: ([URL]) -> Void = { _ in }
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = ComposerNSTextView()
        applyAppearance(colorScheme, scrollView: scroll, textView: tv)
        tv.delegate = context.coordinator
        tv.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.submit()
        }
        tv.onDropFileURLs = { [weak coordinator = context.coordinator] urls in
            coordinator?.dropFileURLs(urls)
        }
        tv.registerForDraggedTypes([.fileURL])
        tv.isRichText = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.insertionPointColor = caretColor
        tv.selectedTextAttributes = [.backgroundColor: selectionColor]
        tv.font = font
        tv.textContainerInset = NSSize(width: 4, height: 10)
        tv.textContainer?.lineFragmentPadding = 0
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 36)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = tv
        context.coordinator.textView = tv
        tv.string = text
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? ComposerNSTextView else { return }
        context.coordinator.parent = self
        applyAppearance(colorScheme, scrollView: scrollView, textView: tv)
        tv.font = font
        tv.insertionPointColor = caretColor
        tv.selectedTextAttributes = [.backgroundColor: selectionColor]
        tv.isEditable = isEnabled
        tv.isSelectable = isEnabled
        tv.onDropFileURLs = { [weak coordinator = context.coordinator] urls in
            coordinator?.dropFileURLs(urls)
        }
        if tv.string != text {
            tv.string = text
        }

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(tv)
            }
        }
        tv.needsDisplay = true
    }

    private func applyAppearance(_ scheme: ColorScheme, scrollView: NSScrollView, textView: NSTextView) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        scrollView.appearance = appearance
        textView.appearance = appearance
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineChatComposer
        weak var textView: ComposerNSTextView?
        var lastFocusRequest = 0

        init(_ parent: MultilineChatComposer) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func submit() {
            parent.onSubmit()
        }

        func dropFileURLs(_ urls: [URL]) {
            parent.onDropFileURLs(urls)
        }
    }
}

final class ComposerNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onDropFileURLs: (([URL]) -> Void)?

    override var isOpaque: Bool { false }

    override func keyDown(with event: NSEvent) {
        let returnKeys: [UInt16] = [36, 76]
        if returnKeys.contains(event.keyCode), !event.modifierFlags.contains(.shift) {
            if isEditable {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !draggedFileURLs(from: sender).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !draggedFileURLs(from: sender).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = draggedFileURLs(from: sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onDropFileURLs?(urls)
        return true
    }

    private func draggedFileURLs(from sender: NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }
}

extension NSColor {
    static let prismAccentCaret = NSColor(red: 1.0, green: 0.44, blue: 0.26, alpha: 0.95)
}
