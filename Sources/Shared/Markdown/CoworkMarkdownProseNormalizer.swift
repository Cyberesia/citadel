import Foundation

/// LLM output often concatenates headings, uses `---` / long em-dash runs, etc.
/// This normalizer should be MINIMAL to avoid breaking valid Markdown spans (like multi-line bold).
enum CoworkMarkdownProseNormalizer {

    /// Minimal normalization to clean up LLM-specific artifacts without breaking Markdown syntax.
    static func softened(_ source: String) -> String {
        var s = source.replacingOccurrences(of: "\r\n", with: "\n")

        // 1) Nettoyage des lignes de séparation CommonMark (---, ***, ___)
        // On évite de toucher aux lignes de tableaux.
        s = replaceLines(
            matching: #"^(?!.*\|)\s*((?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})\s*$"#,
            in: s,
            replacement: "\n\n"
        )

        // 2) Suppression des lignes décoratives de tirets cadratins `————`
        s = replaceLines(
            matching: #"^(?!.*\|)[\s\u2013\u2014\-]{6,}\s*$"#,
            in: s,
            replacement: ""
        )

        // 3) Ajout de sauts de ligne AVANT les éléments structurels uniquement s'ils sont collés au texte précédent.
        // Cela évite l'effet "mur de texte" sans casser le contenu des paragraphes.
        s = insertBlankLinesBeforeStructuralMarkdownRows(s)

        // 4) Certains LLM écrivent des sections séparées comme `1. Titre`, puis recommencent `1.`
        // plus bas. Comme chaque bloc Markdown devient une liste distincte, le rendu redémarre à 1.
        s = renumberRepeatedTopLevelOnes(s)

        s = collapseBlankRuns(s)
        return s
    }

    /// Insère une ligne vide avant les titres, listes et rubriques uniquement s'ils sont sur une nouvelle ligne collée.
    private static func insertBlankLinesBeforeStructuralMarkdownRows(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        guard lines.count > 1 else { return source }

        func isStructural(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            if t.hasPrefix("#") { return true } // Headings
            if t.range(of: #"^\s*[-*+]\s"#, options: .regularExpression) != nil { return true } // Bullet list
            if t.range(of: #"^\s*\d+\.\s"#, options: .regularExpression) != nil { return true } // Ordered list
            if t.hasPrefix("|") && t.contains("|") { return true } // Table
            return false
        }

        var out: [String] = []
        for (idx, line) in lines.enumerated() {
            if idx > 0 {
                let prev = lines[idx - 1]
                if !line.isEmpty && !prev.isEmpty && isStructural(line) {
                    // Si la ligne précédente ne finit pas déjà par un blanc, on en ajoute un.
                    if let last = out.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                        out.append("")
                    }
                }
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    private static func renumberRepeatedTopLevelOnes(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        let regex = try! NSRegularExpression(pattern: #"^(\s*)1\.\s+"#)
        let matchCount = lines.reduce(0) { partial, line in
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            return partial + (regex.firstMatch(in: line, range: range) == nil ? 0 : 1)
        }
        guard matchCount > 1 else { return source }

        var next = 1
        return lines.map { line in
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: line, range: range) else { return line }
            defer { next += 1 }
            let indent = match.numberOfRanges > 1 ? ns.substring(with: match.range(at: 1)) : ""
            return regex.stringByReplacingMatches(
                in: line,
                options: [],
                range: match.range,
                withTemplate: "\(indent)\(next). "
            )
        }.joined(separator: "\n")
    }

    private static func replaceLines(
        matching pattern: String,
        in string: String,
        replacement: String
    ) -> String {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        return regex.stringByReplacingMatches(
            in: string,
            options: [],
            range: NSRange(location: 0, length: (string as NSString).length),
            withTemplate: replacement
        )
    }

    private static func collapseBlankRuns(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\n{4,}", with: "\n\n\n", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t
    }
}
