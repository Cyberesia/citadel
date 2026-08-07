import Foundation

/// GitHub-Flavored Markdown pipe tables are **not** supported by `AttributedString(markdown:)`.
/// We detect table blocks and render them separately (SwiftUI grid + plain layout for PDF).
enum CoworkMarkdownDocumentSegment: Equatable {
    case markdown(String)
    case table(rows: [[String]])
}

enum CoworkGFMTableMarkdown {

    /// Splits markdown into alternating prose fragments and parsed pipe tables (header + body rows).
    ///
    /// **Important:** cette étape utilise le texte « brut » (seuls `\r\n` → `\n`).
    /// Ne pas appeler `CoworkMarkdownProseNormalizer` ici : il insère des sauts au milieu des lignes `| … |`
    /// (ex. `**a** **b**`) et empêche alors de reconnaître les tableaux GFM.
    static func segments(from source: String) -> [CoworkMarkdownDocumentSegment] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).map(
            Self.fixDoubleLeadingPipeRow
        )

        var result: [CoworkMarkdownDocumentSegment] = []
        var buf: [String] = []
        var i = 0

        func flushBuf() {
            guard !buf.isEmpty else { return }
            let text = buf.joined(separator: "\n")
            buf = []
            guard !text.isEmpty else { return }
            result.append(.markdown(text))
        }

        while i < lines.count {
            if let (table, next) = parseTable(lines: lines, start: i) {
                flushBuf()
                result.append(.table(rows: table))
                i = next
            } else {
                buf.append(lines[i])
                i += 1
            }
        }
        flushBuf()
        return result
    }

    /// PDF de document généré uniquement : répare les tableaux GFM cassés par sauts de ligne (cellules ou lignes coupées).
    static func repairSplitTableRowsForPDFExport(_ source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).map(
            fixDoubleLeadingPipeRow
        )
        mergeBareContinuationAfterPipeLine(&lines)

        var spans: [(start: Int, end: Int, columns: Int)] = []
        var scan = 0
        while scan < lines.count {
            if let (table, end) = parseTable(lines: lines, start: scan) {
                spans.append((scan, end, table[0].count))
                scan = end
            } else {
                scan += 1
            }
        }
        for span in spans.reversed() {
            let bodyStart = span.start + 2
            guard bodyStart < span.end else { continue }
            mergeSplitRowsInTableBody(
                lines: &lines,
                bodyStart: bodyStart,
                bodyEnd: span.end,
                columns: span.columns
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Fusionne `ligne sans |\nsuite` sur la ligne précédente si celle-ci contient un pipe (suite de cellule hors `|`).
    private static func mergeBareContinuationAfterPipeLine(_ lines: inout [String]) {
        var i = 0
        while i < lines.count - 1 {
            let next = lines[i + 1]
            if next.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }
            let pipeCount = lines[i].filter { $0 == "|" }.count
            // Au moins 2 « | » → ressemble à une ligne de tableau (évite les faux positifs avec un seul pipe).
            if pipeCount >= 2, !next.contains("|") {
                lines[i] =
                    lines[i].trimmingCharacters(in: .whitespaces) + " "
                    + next.trimmingCharacters(in: .whitespaces)
                lines.remove(at: i + 1)
                continue
            }
            i += 1
        }
    }

    private static func mergeSplitRowsInTableBody(
        lines: inout [String],
        bodyStart: Int,
        bodyEnd: Int,
        columns: Int
    ) {
        guard bodyStart < bodyEnd else { return }
        var newBody: [String] = []
        var k = bodyStart
        while k < bodyEnd {
            var row = lines[k]
            k += 1
            var safety = 0
            while parsePipeRow(row).count < columns && k < bodyEnd && safety < 40 {
                safety += 1
                let next = lines[k]
                if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                row =
                    row.trimmingCharacters(in: .whitespaces) + " "
                    + next.trimmingCharacters(in: .whitespaces)
                k += 1
            }
            newBody.append(row)
        }
        lines.replaceSubrange(bodyStart ..< bodyEnd, with: newBody)
    }

    // MARK: - Parsing

    /// Certains modèles préfixent une ligne de tableau avec `||` au lieu de `|`.
    private static func fixDoubleLeadingPipeRow(_ line: String) -> String {
        guard line.contains("|") else { return line }
        guard line.range(of: #"^\s*\|\|"#, options: .regularExpression) != nil else { return line }
        return line.replacingOccurrences(of: #"^\s*\|\|"#, with: "|", options: .regularExpression)
    }

    private static func parseTable(lines: [String], start: Int) -> (rows: [[String]], end: Int)? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start]
        let sepLine = lines[start + 1]
        guard looksLikePipeRow(headerLine), isSeparatorRow(sepLine) else { return nil }

        let header = parsePipeRow(headerLine)
        let sepCells = parsePipeRow(sepLine)
        guard header.count >= 2, sepCells.count == header.count else { return nil }

        let columns = header.count
        var rows: [[String]] = [normalizeCells(header, columns: columns)]

        var idx = start + 2
        while idx < lines.count {
            let raw = lines[idx]
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard looksLikePipeRow(raw) else { break }
            let row = normalizeCells(parsePipeRow(raw), columns: columns)
            rows.append(row)
            idx += 1
        }
        guard rows.count >= 2 else { return nil }
        return (rows, idx)
    }

    private static func looksLikePipeRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = parsePipeRow(line)
        guard cells.count >= 2 else { return false }
        return cells.allSatisfy(isAlignmentCell)
    }

    /// A GFM separator cell is one of: `---`, `:---`, `---:`, `:---:` (spaces allowed).
    private static func isAlignmentCell(_ cell: String) -> Bool {
        let t = cell.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        var core = t
        if core.hasPrefix(":") { core.removeFirst() }
        if core.hasSuffix(":") { core.removeLast() }
        core = core.trimmingCharacters(in: .whitespaces)
        guard core.count >= 3 else { return false }
        return core.allSatisfy { $0 == "-" }
    }

    /// Splits a table row on `|` (GFM style); trims cells; drops leading/trailing empty from outer pipes.
    private static func parsePipeRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        let parts = s.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        return parts
    }

    private static func normalizeCells(_ cells: [String], columns: Int) -> [String] {
        var row = cells
        if row.count < columns {
            row.append(contentsOf: Array(repeating: "", count: columns - row.count))
        } else if row.count > columns {
            row = Array(row.prefix(columns))
        }
        return row
    }
}
