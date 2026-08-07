import AppKit
import SwiftUI

/// Murmura-class chat body: AppKit selectable prose + bordered GFM tables (not monospace PDF layout).
struct CoworkMarkdownMessageText: View {
    let source: String
    var baseSize: CGFloat = 12

    var body: some View {
        if source.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: max(8, baseSize * 0.55)) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .markdown(let fragment):
                        CoworkSelectableMarkdownText(source: fragment, baseSize: baseSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    case .table(let rows):
                        CoworkMarkdownTableBlock(rows: rows, baseSize: baseSize)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var segments: [CoworkMarkdownDocumentSegment] {
        CoworkGFMTableMarkdown.segments(from: source)
    }
}

/// Bordered alternating-row table — same visual language as Murmura’s MarkdownUI tables.
private struct CoworkMarkdownTableBlock: View {
    let rows: [[String]]
    let baseSize: CGFloat
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    copyTable()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(didCopy ? "Copied" : "Copy table")
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(plainCell(cell))
                                    .font(.system(
                                        size: baseSize,
                                        weight: rowIndex == 0 ? .semibold : .regular
                                    ))
                                    .foregroundStyle(PrismTheme.textPrimary)
                                    .frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .trailing) {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.18))
                                            .frame(width: 1)
                                    }
                            }
                        }
                        .background(
                            rowIndex == 0
                                ? Color.secondary.opacity(0.12)
                                : (rowIndex.isMultiple(of: 2)
                                    ? Color.secondary.opacity(0.06)
                                    : Color.secondary.opacity(0.10))
                        )
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.22))
                                .frame(height: 1)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .markdownTableMargin(baseSize: baseSize)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plainCell(_ markdown: String) -> String {
        var t = markdown
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "<br>", with: " ", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: "*", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func copyTable() {
        let markdown = rows.enumerated().map { index, row in
            let line = "| " + row.joined(separator: " | ") + " |"
            if index == 0 {
                let sep = "| " + row.map { _ in "---" }.joined(separator: " | ") + " |"
                return line + "\n" + sep
            }
            return line
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopy = false
        }
    }
}

private extension View {
    func markdownTableMargin(baseSize: CGFloat) -> some View {
        padding(.vertical, max(6, baseSize * 0.45))
    }
}

private struct CoworkSelectableMarkdownText: NSViewRepresentable {
    let source: String
    let baseSize: CGFloat

    func makeNSView(context: Context) -> CoworkSelectableMarkdownContainer {
        let view = CoworkSelectableMarkdownContainer()
        view.setAttributedText(renderedText(source))
        context.coordinator.lastSource = source
        context.coordinator.lastRenderAt = Date()
        return view
    }

    func updateNSView(_ nsView: CoworkSelectableMarkdownContainer, context: Context) {
        let coordinator = context.coordinator
        guard source != coordinator.lastSource else { return }
        // Live stream: avoid full attributed rebuild on every tiny delta (Murmura batches ~22ms / 560 chars upstream).
        let now = Date()
        if let last = coordinator.lastRenderAt,
           now.timeIntervalSince(last) < 0.09,
           source.count - coordinator.lastSource.count < 220,
           source.hasPrefix(coordinator.lastSource) {
            coordinator.pendingSource = source
            coordinator.scheduleFlush(for: nsView, render: renderedText)
            return
        }
        coordinator.cancelFlush()
        coordinator.pendingSource = nil
        coordinator.lastSource = source
        coordinator.lastRenderAt = now
        nsView.setAttributedText(renderedText(source))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func renderedText(_ source: String) -> NSAttributedString {
        // Chat prose path — NOT the PDF exporter (that was flattening tables into monospace columns).
        let rendered = CoworkMarkdownFormatting.nsAttributedMarkdownFragmentOnly(source, baseFontSize: baseSize)
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

    final class Coordinator {
        var lastSource = ""
        var lastRenderAt: Date?
        var pendingSource: String?
        private var flushTask: Task<Void, Never>?

        func cancelFlush() {
            flushTask?.cancel()
            flushTask = nil
        }

        func scheduleFlush(
            for view: CoworkSelectableMarkdownContainer,
            render: @escaping (String) -> NSAttributedString
        ) {
            guard flushTask == nil else { return }
            flushTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard !Task.isCancelled, let pending = pendingSource else {
                    flushTask = nil
                    return
                }
                pendingSource = nil
                lastSource = pending
                lastRenderAt = Date()
                view.setAttributedText(render(pending))
                flushTask = nil
            }
        }
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
