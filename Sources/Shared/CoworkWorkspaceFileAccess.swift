import Foundation

/// Resolve and read files from a user-picked workspace folder on disk (fallback when CoworkCore FS APIs fail).
enum CoworkWorkspaceFileAccess {
    static func resolveAbsolutePath(relativePath: String, workspace: String?) -> String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") { return trimmed }
        guard let workspace, !workspace.isEmpty else { return trimmed }
        return (workspace as NSString).appendingPathComponent(trimmed)
    }

    static func isReadable(at absolutePath: String) -> Bool {
        FileManager.default.isReadableFile(atPath: absolutePath)
    }

    static func readData(at absolutePath: String) -> Data? {
        guard isReadable(at: absolutePath) else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: absolutePath))
    }

    static func readBase64(at absolutePath: String) -> String? {
        readData(at: absolutePath)?.base64EncodedString()
    }

    static func readText(at absolutePath: String) -> String? {
        if let data = readData(at: absolutePath),
           let utf8 = String(data: data, encoding: .utf8),
           !utf8.isEmpty {
            return utf8
        }
        return CoworkDocumentTextExtractor.extractText(from: URL(fileURLWithPath: absolutePath))
    }
}
