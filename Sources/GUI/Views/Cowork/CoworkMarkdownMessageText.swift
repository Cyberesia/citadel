import AppKit
import SwiftUI

/// Murmura-class selectable markdown body for chat bubbles (code, bold, tables).
struct CoworkMarkdownMessageText: View {
    let source: String
    var baseSize: CGFloat = 12

    var body: some View {
        if source.isEmpty {
            EmptyView()
        } else {
            CoworkSelectableMarkdownText(source: source, baseSize: baseSize)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CoworkSelectableMarkdownText: NSViewRepresentable {
    let source: String
    let baseSize: CGFloat

    func makeNSView(context: Context) -> CoworkSelectableMarkdownContainer {
        let view = CoworkSelectableMarkdownContainer()
        view.setAttributedText(renderedText)
        return view
    }

    func updateNSView(_ nsView: CoworkSelectableMarkdownContainer, context: Context) {
        nsView.setAttributedText(renderedText)
    }

    private var renderedText: NSAttributedString {
        let rendered = CoworkMarkdownFormatting.nsAttributedFromMarkdownProcVerbalPDF(source, baseFontSize: baseSize)
        let mutable = NSMutableAttributedString(attributedString: rendered)
        let full = NSRange(location: 0, length: mutable.length)
        guard full.length > 0 else { return mutable }
        mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        mutable.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.lineSpacing = max(1, baseSize * 0.08)
            style.paragraphSpacing = max(5, baseSize * 0.35)
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return mutable
    }
}

final class CoworkSelectableMarkdownContainer: NSView {
    private let textView = NSTextView(frame: .zero)
    private var lastMeasuredWidth: CGFloat = 0
    private var cachedHeight: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.importsGraphics = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.labelColor.withAlphaComponent(0.18)
        ]
        addSubview(textView)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    func setAttributedText(_ attributed: NSAttributedString) {
        textView.textStorage?.setAttributedString(attributed)
        invalidateMeasuredHeight()
    }

    override func layout() {
        super.layout()
        textView.frame = bounds
        updateTextContainerSize(width: bounds.width)
        if abs(bounds.width - lastMeasuredWidth) > 0.5 {
            invalidateMeasuredHeight()
        }
    }

    override var intrinsicContentSize: NSSize {
        let width = max(bounds.width, 1)
        if abs(width - lastMeasuredWidth) > 0.5 {
            recalculateHeight(width: width)
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: cachedHeight)
    }

    private func invalidateMeasuredHeight() {
        lastMeasuredWidth = 0
        invalidateIntrinsicContentSize()
    }

    private func updateTextContainerSize(width: CGFloat) {
        textView.textContainer?.containerSize = NSSize(
            width: max(width, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func recalculateHeight(width: CGFloat) {
        updateTextContainerSize(width: width)
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            cachedHeight = 1
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        cachedHeight = max(1, ceil(used.height + textView.textContainerInset.height * 2 + 2))
        lastMeasuredWidth = width
    }
}
