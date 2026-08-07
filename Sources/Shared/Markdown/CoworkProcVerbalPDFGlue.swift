import Foundation

/// Normalisations **minimales** pour l'export PDF du document généré.
/// On laisse le soin au composant `swift-markdown-ui` de gérer le rendu Markdown.
enum CoworkProcVerbalPDFGlue {

    static func softenFragmentForPDFExport(_ fragment: String) -> String {
        // On délègue au normalizer minimaliste.
        var s = CoworkMarkdownProseNormalizer.softened(fragment)
        
        // On évite tout traitement regex qui pourrait casser les balises ** ou les listes.
        s = collapseExcessiveBlankLines(s)
        return s
    }

    private static func collapseExcessiveBlankLines(_ source: String) -> String {
        var t = source.replacingOccurrences(of: "\n{4,}", with: "\n\n\n", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t
    }
}
