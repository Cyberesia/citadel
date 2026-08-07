import Foundation

struct CoworkDocumentExcerpt: Identifiable, Hashable {
    let id: String
    let filename: String
    let content: String
}

struct CoworkParsedUserMessage: Hashable {
    var excerpts: [CoworkDocumentExcerpt]
    var userText: String

    var hasExcerpts: Bool { !excerpts.isEmpty }
}

/// Parses user messages that include inlined document excerpts (sent to the model, rendered separately in UI).
enum CoworkDocumentContextParser {
    private static let beginMarker = "[[citadel-docs]]"
    private static let endMarker = "[[/citadel-docs]]"

    static func wrapDocumentBlocks(_ blocks: [String], userText: String) -> String {
        guard !blocks.isEmpty else { return userText }
        return """
        \(beginMarker)
        \(L10n.documentContextHeader)

        \(blocks.joined(separator: "\n\n"))
        \(endMarker)

        \(userText)
        """
    }

    static func parse(_ source: String) -> CoworkParsedUserMessage {
        if let range = source.range(of: beginMarker),
           let endRange = source.range(of: endMarker, range: range.upperBound..<source.endIndex) {
            let body = String(source[range.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: L10n.documentContextHeader, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(source[endRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CoworkParsedUserMessage(
                excerpts: parseExcerptBlocks(body),
                userText: tail
            )
        }
        return parseLegacy(source)
    }

    private static func parseLegacy(_ source: String) -> CoworkParsedUserMessage {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("--- ") else {
            return CoworkParsedUserMessage(excerpts: [], userText: trimmed)
        }

        if let separatorRange = trimmed.range(of: "\n---\n\n", options: .backwards) {
            let head = String(trimmed[..<separatorRange.lowerBound])
            let tail = String(trimmed[separatorRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = head
                .replacingOccurrences(of: L10n.documentContextHeader, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CoworkParsedUserMessage(
                excerpts: parseExcerptBlocks(body),
                userText: tail
            )
        }

        return CoworkParsedUserMessage(excerpts: [], userText: trimmed)
    }

    private static func parseExcerptBlocks(_ body: String) -> [CoworkDocumentExcerpt] {
        guard !body.isEmpty else { return [] }
        let parts = body.components(separatedBy: "\n\n--- ")
        var excerpts: [CoworkDocumentExcerpt] = []

        for (index, part) in parts.enumerated() {
            let chunk = index == 0 ? part : "--- " + part
            guard let parsed = parseSingleExcerpt(chunk) else { continue }
            excerpts.append(parsed)
        }
        return excerpts
    }

    private static func parseSingleExcerpt(_ chunk: String) -> CoworkDocumentExcerpt? {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("--- "),
              let closeRange = trimmed.range(of: " ---\n") else { return nil }
        let filename = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let content = String(trimmed[closeRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty, !content.isEmpty else { return nil }
        return CoworkDocumentExcerpt(id: filename, filename: filename, content: content)
    }
}
