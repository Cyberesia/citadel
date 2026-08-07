import Foundation

/// Picks workspace documents to inline in a user message — filename, Spotlight content, local text, then open prompts.
enum CoworkWorkspaceDocumentMatcher {
    private static let maxAutoInclude = 8
    private static let minFilenameTokenLength = 2
    private static let minContentTokenLength = 3
    private static let maxLocalContentScan = 24

    private static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "can", "was", "our", "out", "how", "why",
        "what", "when", "where", "which", "this", "that", "those", "these", "from", "with", "have", "has",
        "had", "will", "would", "could", "should", "about", "into", "your", "their", "there", "then", "than",
        "les", "des", "une", "dans", "pour", "par", "sur", "sans", "avec", "est", "pas", "plus", "aux",
        "cette", "sont", "qui", "que", "quoi", "dont", "ces", "cela", "elle", "elles", "nous", "vous",
        "de", "du", "la", "le", "en", "un", "et", "ou", "ce", "se", "sa", "son", "ses", "mon", "mes",
    ]

    /// Returns absolute paths of workspace documents relevant to the user query.
    static func matchingPaths(workspace: String, query: String) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            matchingPathsSync(workspace: workspace, query: query)
        }.value
    }

    private static func matchingPathsSync(workspace: String, query: String) -> [String] {
        let docs = listDocuments(in: workspace)
        guard !docs.isEmpty else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let docSet = Set(docs)
        var ordered: [String] = []
        var seen = Set<String>()

        func appendUnique(_ paths: [String]) {
            for path in paths where docSet.contains(path) && seen.insert(path).inserted && ordered.count < maxAutoInclude {
                ordered.append(path)
            }
        }

        appendUnique(matchByFilenameTokens(query: trimmed, docs: docs))

        let contentTokens = contentSearchTokens(from: trimmed)
        if !contentTokens.isEmpty {
            let spotlightHits = CoworkWorkspaceSpotlightSearch.matchingPaths(in: workspace, tokens: contentTokens)
            appendUnique(spotlightHits)
            appendUnique(matchByExtractedContent(tokens: contentTokens, docs: docs))
        }

        if ordered.isEmpty, shouldIncludeWholeWorkspace(query: trimmed, documentCount: docs.count) {
            return Array(docs.prefix(maxAutoInclude))
        }
        return ordered
    }

    // MARK: - Filename

    private static func matchByFilenameTokens(query: String, docs: [String]) -> [String] {
        let tokens = filenameTokens(from: query)
        guard !tokens.isEmpty else { return [] }

        return docs.filter { path in
            let normalized = normalizedFilename(path)
            let fileTokens = tokenize(normalized)
            return tokens.contains { token in
                normalized.contains(token) || fileTokens.contains(where: { overlaps($0, token) })
            }
        }
    }

    // MARK: - Local extracted content (Spotlight fallback)

    private static func matchByExtractedContent(tokens: [String], docs: [String]) -> [String] {
        docs.prefix(maxLocalContentScan).filter { path in
            guard let text = CoworkDocumentTextExtractor.extractText(from: URL(fileURLWithPath: path))?.lowercased(),
                  !text.isEmpty else { return false }
            return tokens.contains { text.contains($0) }
        }
    }

    private static func contentSearchTokens(from query: String) -> [String] {
        tokenize(query.lowercased())
            .filter { $0.count >= minContentTokenLength && !stopwords.contains($0) }
    }

    private static func filenameTokens(from query: String) -> [String] {
        tokenize(query.lowercased()).filter { $0.count >= minFilenameTokenLength }
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func normalizedFilename(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
    }

    private static func overlaps(_ a: String, _ b: String) -> Bool {
        a.contains(b) || b.contains(a)
    }

    // MARK: - Whole-folder fallback

    private static func shouldIncludeWholeWorkspace(query: String, documentCount: Int) -> Bool {
        guard documentCount > 0, documentCount <= maxAutoInclude else { return false }
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        if query.contains("?") { return words.count >= 2 }
        return words.count >= 4
    }

    private static func listDocuments(in workspace: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: workspace) else { return [] }
        return entries.compactMap { name -> String? in
            let path = (workspace as NSString).appendingPathComponent(name)
            guard CoworkIndexableDocumentTypes.isIndexable(path: path) else { return nil }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
            return path
        }
        .sorted {
            ($0 as NSString).lastPathComponent.localizedCaseInsensitiveCompare(($1 as NSString).lastPathComponent) == .orderedAscending
        }
    }
}
