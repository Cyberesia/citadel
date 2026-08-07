import Foundation
import PDFKit

/// Native macOS text extraction for PDF, DOCX, RTF and plain text (Murmura-class).
enum CoworkDocumentTextExtractor {
    static let maxCharacters = 48_000

    static func cleanForDisplay(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return extractFromPDF(url)
        case "docx":
            return extractFromRichFormat(url, type: .officeOpenXML)
        case "rtf":
            return extractFromRichFormat(url, type: .rtf)
        case "rtfd":
            return extractFromRichFormat(url, type: .rtfd)
        default:
            return extractFromPlainText(url)
        }
    }

    private static func extractFromPDF(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var fullText = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                fullText += pageText + "\n"
            }
            if fullText.count > maxCharacters {
                return String(fullText.prefix(maxCharacters)) + "\n… [truncated]"
            }
        }
        return fullText.isEmpty ? nil : fullText
    }

    private static func extractFromRichFormat(_ url: URL, type: NSAttributedString.DocumentType) -> String? {
        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
            let attrString = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            return truncate(attrString.string)
        } catch {
            return nil
        }
    }

    private static func extractFromPlainText(_ url: URL) -> String? {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return truncate(utf8) }
        if let ascii = try? String(contentsOf: url, encoding: .ascii) { return truncate(ascii) }
        return nil
    }

    private static func truncate(_ text: String) -> String {
        if text.count > maxCharacters {
            return String(text.prefix(maxCharacters)) + "\n… [truncated]"
        }
        return text
    }
}
