import AppKit
import Foundation

/// Shared Markdown → attributed text for PDF / RTF; uses system parsers for prose.
/// GFM pipe tables are handled explicitly (Apple’s parser ignores them and flattens rows).
enum CoworkMarkdownFormatting {

    /// Parsed markdown with a default body font where runs don’t specify one.
    static func nsAttributedFromMarkdown(_ markdown: String, baseFontSize: CGFloat = 12) -> NSAttributedString {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: "")
        }

        let segments = CoworkGFMTableMarkdown.segments(from: trimmed)
        guard !segments.isEmpty else {
            return NSAttributedString(string: trimmed, attributes: [.font: NSFont.systemFont(ofSize: baseFontSize)])
        }

        let root = NSMutableAttributedString()
        let separator = NSAttributedString(
            string: "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: baseFontSize)]
        )

        for (idx, seg) in segments.enumerated() {
            if idx > 0 { root.append(separator) }
            switch seg {
            case .markdown(let fragment):
                let prose = CoworkMarkdownProseNormalizer.softened(fragment)
                root.append(nsAttributedMarkdownFragment(prose, baseFontSize: baseFontSize))
            case .table(let rows):
                root.append(nsAttributedTable(rows, baseFontSize: baseFontSize))
            }
        }

        return root
    }

    /// Conversion Markdown → `NSAttributedString` **pour l’export PDF de document généré uniquement**.
    /// N’impacte pas le rendu chat (`MarkdownMessageText`).
    static func nsAttributedFromMarkdownProcVerbalPDF(_ markdown: String, baseFontSize: CGFloat = 12) -> NSAttributedString {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: "")
        }

        let repairedTables = CoworkGFMTableMarkdown.repairSplitTableRowsForPDFExport(trimmed)
        let segments = CoworkGFMTableMarkdown.segments(from: repairedTables)
        guard !segments.isEmpty else {
            return NSAttributedString(string: trimmed, attributes: [.font: NSFont.systemFont(ofSize: baseFontSize)])
        }

        let root = NSMutableAttributedString()
        let separator = NSAttributedString(
            string: "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: baseFontSize)]
        )

        for (idx, seg) in segments.enumerated() {
            if idx > 0 { root.append(separator) }
            switch seg {
            case .markdown(let fragment):
                let prose = CoworkProcVerbalPDFGlue.softenFragmentForPDFExport(fragment)
                root.append(renderProseBlocksForPDFExport(prose, baseFontSize: baseFontSize))
            case .table(let rows):
                root.append(nsAttributedTableProcVerbalPDF(rows, baseFontSize: baseFontSize))
            }
        }

        return root
    }

    // MARK: - PDF PV : rendu bloc par bloc (pour que headings, paragraphes et listes soient vraiment séparés)

    /// Apple’s `NSAttributedString(markdown: .full)` concatenates block elements without newline
    /// separators — the PresentationIntent attribute is meant to drive layout, but a plain
    /// `NSTextView` ignores it. We parse blocks ourselves and insert real `\n\n`.
    private static func renderProseBlocksForPDFExport(_ source: String, baseFontSize: CGFloat) -> NSAttributedString {
        let blocks = parseProseBlocksForPDFExport(source)
        let out = NSMutableAttributedString()
        let blockGap = NSAttributedString(
            string: "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: baseFontSize)]
        )

        for (idx, block) in blocks.enumerated() {
            if idx > 0 { out.append(blockGap) }
            out.append(render(block: block, baseFontSize: baseFontSize))
        }
        return out
    }

    private enum ProseBlock: Equatable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case bulletList(items: [String])
        case orderedList(start: Int, items: [String])
    }

    private static func parseProseBlocksForPDFExport(_ source: String) -> [ProseBlock] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")
        var blocks: [ProseBlock] = []
        var i = 0

        let headingRegex = try! NSRegularExpression(pattern: #"^\s*(#{1,6})\s+(.+?)\s*#*\s*$"#, options: [])
        let hrRegex = try! NSRegularExpression(
            pattern: #"^\s*(?:[-*_]\s*){3,}\s*$"#,
            options: []
        )
        let bulletRegex = try! NSRegularExpression(pattern: #"^\s*[-*+]\s+"#, options: [])
        let orderedRegex = try! NSRegularExpression(pattern: #"^\s*(\d+)\.\s+"#, options: [])

        func matches(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
            let range = NSRange(location: 0, length: (s as NSString).length)
            return re.firstMatch(in: s, options: [], range: range)
        }

        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if matches(hrRegex, trimmed) != nil {
                i += 1
                continue
            }

            if let m = matches(headingRegex, line) {
                let ns = line as NSString
                let hashes = ns.substring(with: m.range(at: 1))
                let text = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: hashes.count, text: text))
                i += 1
                continue
            }

            if matches(bulletRegex, line) != nil {
                var items: [String] = []
                while i < rawLines.count {
                    let l = rawLines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if let m = matches(bulletRegex, l) {
                        let rest = (l as NSString).substring(from: m.range.upperBound)
                        items.append(rest.trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else if !items.isEmpty,
                        matches(headingRegex, l) == nil,
                        matches(orderedRegex, l) == nil
                    {
                        items[items.count - 1] += " " + t
                        i += 1
                    } else {
                        break
                    }
                }
                if !items.isEmpty { blocks.append(.bulletList(items: items)) }
                continue
            }

            if matches(orderedRegex, line) != nil {
                var items: [String] = []
                var start = 1
                while i < rawLines.count {
                    let l = rawLines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if let m = matches(orderedRegex, l) {
                        if items.isEmpty, m.numberOfRanges > 1 {
                            start = Int((l as NSString).substring(with: m.range(at: 1))) ?? 1
                        }
                        let rest = (l as NSString).substring(from: m.range.upperBound)
                        items.append(rest.trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else if !items.isEmpty,
                        matches(headingRegex, l) == nil,
                        matches(bulletRegex, l) == nil
                    {
                        items[items.count - 1] += " " + t
                        i += 1
                    } else {
                        break
                    }
                }
                if !items.isEmpty { blocks.append(.orderedList(start: start, items: items)) }
                continue
            }

            // Paragraph: accumule les lignes non vides qui ne sont pas un autre bloc.
            var paraLines: [String] = [line]
            i += 1
            while i < rawLines.count {
                let l = rawLines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if matches(headingRegex, l) != nil
                    || matches(hrRegex, t) != nil
                    || matches(bulletRegex, l) != nil
                    || matches(orderedRegex, l) != nil
                {
                    break
                }
                paraLines.append(l)
                i += 1
            }
            blocks.append(.paragraph(text: paraLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func render(block: ProseBlock, baseFontSize: CGFloat) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            let size = headingFontSize(level: level, base: baseFontSize)
            let baseFont = NSFont.boldSystemFont(ofSize: size)
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = 6
            paragraph.paragraphSpacing = 4
            paragraph.lineBreakMode = .byWordWrapping
            let inline = renderInlineMarkdown(text, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inline)
            m.addAttribute(
                .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
            return m

        case .paragraph(let text):
            let baseFont = NSFont.systemFont(ofSize: baseFontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 4
            paragraph.lineBreakMode = .byWordWrapping
            let inline = renderInlineMarkdown(text, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inline)
            m.addAttribute(
                .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
            return m

        case .bulletList(let items):
            return renderList(items: items, baseFontSize: baseFontSize, marker: { _ in "•   " })

        case .orderedList(let start, let items):
            return renderList(items: items, baseFontSize: baseFontSize, marker: { i in "\(start + i).  " })
        }
    }

    private static func renderList(
        items: [String],
        baseFontSize: CGFloat,
        marker: (Int) -> String
    ) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: baseFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacing = 3
        paragraph.headIndent = baseFontSize * 1.4
        paragraph.firstLineHeadIndent = 0
        paragraph.lineSpacing = 2

        let out = NSMutableAttributedString()
        for (k, item) in items.enumerated() {
            if k > 0 {
                out.append(
                    NSAttributedString(
                        string: "\n",
                        attributes: [.font: baseFont, .paragraphStyle: paragraph]
                    ))
            }
            let bullet = NSAttributedString(
                string: marker(k),
                attributes: [.font: baseFont, .paragraphStyle: paragraph]
            )
            out.append(bullet)
            let inline = renderInlineMarkdown(item, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inline)
            m.addAttribute(
                .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
            out.append(m)
        }
        return out
    }

    private static func headingFontSize(level: Int, base: CGFloat) -> CGFloat {
        switch level {
        case 1: return base + 8
        case 2: return base + 6
        case 3: return base + 4
        case 4: return base + 2
        default: return base + 1
        }
    }

    /// Inline Markdown uniquement (gras, italique, code, liens) — pas de structure de bloc.
    /// Applique `baseFont` à tout le texte en préservant les traits bold/italic venant du markdown.
    private static func renderInlineMarkdown(_ source: String, baseFont: NSFont) -> NSAttributedString {
        guard !source.isEmpty else { return NSAttributedString(string: "") }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = true
        options.failurePolicy = .returnPartiallyParsedIfPossible

        let fallback: () -> NSAttributedString = {
            NSAttributedString(string: source, attributes: [.font: baseFont])
        }

        guard
            let parsed = try? NSAttributedString(markdown: source, options: options, baseURL: nil)
        else {
            return fallback()
        }

        let m = NSMutableAttributedString(attributedString: parsed)
        let full = NSRange(location: 0, length: m.length)
        guard full.length > 0 else { return fallback() }

        let baseIsBold = baseFont.fontDescriptor.symbolicTraits.contains(.bold)

        m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            let traitsFromMD: NSFontDescriptor.SymbolicTraits = {
                if let existing = value as? NSFont {
                    return existing.fontDescriptor.symbolicTraits
                }
                return []
            }()
            var traits: NSFontDescriptor.SymbolicTraits = []
            if baseIsBold || traitsFromMD.contains(.bold) { traits.insert(.bold) }
            if traitsFromMD.contains(.italic) { traits.insert(.italic) }

            let desc = baseFont.fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: desc, size: baseFont.pointSize) ?? baseFont
            m.addAttribute(.font, value: newFont, range: range)
        }
        return m
    }

    /// Tableaux PV en PDF : police système + colonnes paddées (lisible, pas « code monospace »).
    private static func nsAttributedTableProcVerbalPDF(_ rows: [[String]], baseFontSize: CGFloat) -> NSAttributedString {
        guard !rows.isEmpty else { return NSAttributedString(string: "") }

        let bodyFont = NSFont.systemFont(ofSize: max(baseFontSize - 0.5, 10))
        let headerFont = NSFont.systemFont(ofSize: baseFontSize, weight: .semibold)

        let plainRows: [[String]] = rows.map { row in row.map { plainTableCellProcVerbalPDF($0) } }
        let colCount = plainRows.map(\.count).max() ?? 0
        guard colCount > 0 else { return NSAttributedString(string: "") }

        let widths: [Int] = (0 ..< colCount).map { ci in
            plainRows
                .map { row in
                    guard ci < row.count else { return 0 }
                    return row[ci].count
                }
                .max() ?? 0
        }

        let pad = { (text: String, width: Int) -> String in
            if text.count >= width { return text }
            return text + String(repeating: " ", count: width - text.count)
        }

        let out = NSMutableAttributedString()
        let wrapParagraph = NSMutableParagraphStyle()
        wrapParagraph.lineBreakMode = .byWordWrapping

        let rowParagraph = NSMutableParagraphStyle()
        rowParagraph.lineBreakMode = .byWordWrapping
        rowParagraph.paragraphSpacingBefore = 2
        rowParagraph.paragraphSpacing = 6

        for (rowIndex, row) in plainRows.enumerated() {
            let font = rowIndex == 0 ? headerFont : bodyFont
            var columns: [String] = []
            for ci in 0 ..< colCount {
                let cell = ci < row.count ? row[ci] : ""
                let w = max(widths[ci], 3)
                columns.append(pad(cell, w))
            }
            let line = columns.joined(separator: " │ ") + "\n"
            let ps = rowIndex == 0 ? wrapParagraph : rowParagraph
            out.append(
                NSAttributedString(
                    string: line,
                    attributes: [.font: font, .paragraphStyle: ps]
                ))

            if rowIndex == 0 {
                let rule = widths.map { String(repeating: "─", count: max(3, $0)) }.joined(separator: "─┼─") + "\n"
                out.append(
                    NSAttributedString(
                        string: rule,
                        attributes: [.font: bodyFont, .paragraphStyle: wrapParagraph]
                    ))
            }
        }
        return out
    }

    private static func plainTableCellProcVerbalPDF(_ markdown: String) -> String {
        var t = markdown
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "<br>", with: " ")
        let italic = try! NSRegularExpression(pattern: #"\*([^*]+)\*"#, options: [])
        t = italic.stringByReplacingMatches(
            in: t,
            options: [],
            range: NSRange(location: 0, length: (t as NSString).length),
            withTemplate: "$1"
        )
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func nsAttributedMarkdownFragment(
        _ fragment: String,
        baseFontSize: CGFloat
    ) -> NSAttributedString {
        guard !fragment.isEmpty else { return NSAttributedString(string: "") }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.allowsExtendedAttributes = true

        if let parsed = try? NSAttributedString(
            markdown: fragment,
            options: options,
            baseURL: nil
        ) {
            return fillMissingFonts(parsed, baseSize: baseFontSize)
        }

        return NSAttributedString(
            string: fragment,
            attributes: [.font: NSFont.systemFont(ofSize: baseFontSize)]
        )
    }

    /// Monospace column layout for PDF/RTF (Apple’s markdown path does not render pipe tables).
    private static func nsAttributedTable(_ rows: [[String]], baseFontSize: CGFloat) -> NSAttributedString {
        guard !rows.isEmpty else { return NSAttributedString(string: "") }

        let mono = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
        let headerMono = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .semibold)

        let plainRows: [[String]] = rows.map { row in row.map { plainTableCell($0) } }
        let colCount = plainRows.map(\.count).max() ?? 0
        guard colCount > 0 else { return NSAttributedString(string: "") }

        let widths: [Int] = (0 ..< colCount).map { ci in
            plainRows
                .map { row in
                    guard ci < row.count else { return 0 }
                    return row[ci].count
                }
                .max() ?? 0
        }

        let pad = { (text: String, width: Int) -> String in
            if text.count >= width { return text }
            return text + String(repeating: " ", count: width - text.count)
        }

        let out = NSMutableAttributedString()
        let wrapParagraph = NSMutableParagraphStyle()
        wrapParagraph.lineBreakMode = .byWordWrapping

        for (rowIndex, row) in plainRows.enumerated() {
            let font = rowIndex == 0 ? headerMono : mono
            var columns: [String] = []
            for ci in 0 ..< colCount {
                let cell = ci < row.count ? row[ci] : ""
                let w = max(widths[ci], 3)
                columns.append(pad(cell, w))
            }
            let line = columns.joined(separator: " │ ") + "\n"
            out.append(
                NSAttributedString(
                    string: line,
                    attributes: [.font: font, .paragraphStyle: wrapParagraph]
                ))

            if rowIndex == 0 {
                let rule = widths.map { String(repeating: "─", count: max(3, $0)) }.joined(separator: "─┼─") + "\n"
                out.append(
                    NSAttributedString(
                        string: rule,
                        attributes: [.font: mono, .paragraphStyle: wrapParagraph]
                    ))
            }
        }
        return out
    }

    private static func plainTableCell(_ markdown: String) -> String {
        var t = markdown
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "<br>", with: " ")
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func fillMissingFonts(_ attr: NSAttributedString, baseSize: CGFloat) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: baseSize)
        let mutable = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: mutable.length)
        guard full.length > 0 else { return mutable }

        mutable.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            guard value == nil else { return }
            mutable.addAttribute(.font, value: base, range: range)
        }

        // If nothing had a font at all
        if mutable.length > 0,
            mutable.attribute(.font, at: 0, effectiveRange: nil) == nil
        {
            mutable.addAttribute(.font, value: base, range: full)
        }

        return mutable
    }

    /// Applique un style de paragraphe **à chaque paragraphe** au lieu d’écraser la structure du Markdown converti (PDF).
    static func applyParagraphStylePerParagraph(_ mutable: NSMutableAttributedString, style: NSParagraphStyle) {
        guard mutable.length > 0 else { return }
        let ns = mutable.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) {
            _, _, enclosingRange, _ in
            guard enclosingRange.length > 0 else { return }
            mutable.addAttribute(.paragraphStyle, value: style, range: enclosingRange)
        }
    }
}
