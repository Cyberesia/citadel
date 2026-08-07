import Foundation

/// Workspace document types Citadel can list, search, and extract text from.
enum CoworkIndexableDocumentTypes {
    static let extensions: Set<String> = [
        "pdf", "doc", "docx", "rtf", "rtfd",
        "txt", "md", "markdown", "csv", "tsv", "json", "yaml", "yml", "xml", "html", "htm",
        "ppt", "pptx", "xls", "xlsx", "pages", "numbers", "key",
    ]

    static func isIndexable(path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }
}
