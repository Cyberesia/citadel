import Foundation

/// Text extraction from Office Open XML containers (PPTX, XLSX) via `/usr/bin/unzip`.
enum CoworkOfficeOpenXMLExtractor {
    static func extractText(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pptx":
            let entries = listEntries(in: url).filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            let chunks = entries.sorted().compactMap { readEntry(named: $0, in: url) }.map(stripXMLTags)
            return join(chunks)
        case "xlsx":
            var chunks: [String] = []
            if let shared = readEntry(named: "xl/sharedStrings.xml", in: url) {
                chunks.append(stripXMLTags(shared))
            }
            let sheets = listEntries(in: url).filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            chunks.append(contentsOf: sheets.sorted().compactMap { readEntry(named: $0, in: url) }.map(stripXMLTags))
            return join(chunks)
        default:
            return nil
        }
    }

    private static func join(_ chunks: [String]) -> String? {
        let text = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func listEntries(in url: URL) -> [String] {
        runUnzip(["-Z1", url.path])?
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func readEntry(named entry: String, in url: URL) -> String? {
        runUnzip(["-p", url.path, entry])
    }

    private static func runUnzip(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 1 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func stripXMLTags(_ xml: String) -> String {
        xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
