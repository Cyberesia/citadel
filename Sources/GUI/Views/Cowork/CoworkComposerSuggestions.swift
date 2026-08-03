import SwiftUI

/// One row in the composer suggestion popup (slash command or @file mention).
struct CoworkComposerSuggestion: Identifiable, Hashable {
    enum Kind { case slashCommand, fileMention }

    let kind: Kind
    let insertion: String
    let title: String
    let detail: String?

    var id: String { "\(kind == .slashCommand ? "/" : "@")\(insertion)" }
}

/// Computes suggestions from the current composer text (trigger token at the end).
enum CoworkComposerSuggestionEngine {
    /// Returns the active trigger ("/" or "@") plus its query, if the caret is inside one.
    static func activeTrigger(in text: String) -> (kind: CoworkComposerSuggestion.Kind, query: String)? {
        // Only suggest while typing the last token — mirrors Murmura behavior.
        guard let lastToken = text.split(separator: " ", omittingEmptySubsequences: false).last else { return nil }
        if text.hasPrefix("/"), !text.contains(" ") {
            return (.slashCommand, String(text.dropFirst()))
        }
        if lastToken.hasPrefix("@"), lastToken.count >= 1 {
            return (.fileMention, String(lastToken.dropFirst()))
        }
        return nil
    }

    static func suggestions(
        for text: String,
        slashCommands: [CoworkSlashCommand],
        workspaceEntries: [CoworkFSEntry]
    ) -> [CoworkComposerSuggestion] {
        guard let trigger = activeTrigger(in: text) else { return [] }
        let query = trigger.query.lowercased()

        switch trigger.kind {
        case .slashCommand:
            return slashCommands
                .filter { query.isEmpty || $0.name.lowercased().contains(query) }
                .prefix(8)
                .map {
                    CoworkComposerSuggestion(
                        kind: .slashCommand,
                        insertion: "/\($0.name) ",
                        title: "/\($0.name)",
                        detail: $0.description.flatMap { $0.isEmpty ? nil : CoworkUserFacing.sanitizeFreeText($0) }
                    )
                }
        case .fileMention:
            return workspaceEntries
                .filter { !$0.isDirectory && (query.isEmpty || $0.name.lowercased().contains(query)) }
                .prefix(8)
                .map {
                    CoworkComposerSuggestion(
                        kind: .fileMention,
                        insertion: "@\($0.name) ",
                        title: $0.name,
                        detail: "Workspace file"
                    )
                }
        }
    }

    /// Replaces the trailing trigger token with the chosen suggestion.
    static func apply(_ suggestion: CoworkComposerSuggestion, to text: String) -> String {
        switch suggestion.kind {
        case .slashCommand:
            return suggestion.insertion
        case .fileMention:
            guard let range = text.range(of: "@", options: .backwards) else { return text + suggestion.insertion }
            return String(text[..<range.lowerBound]) + suggestion.insertion
        }
    }
}

/// Floating suggestion list shown above the composer.
struct CoworkComposerSuggestionList: View {
    let suggestions: [CoworkComposerSuggestion]
    let onPick: (CoworkComposerSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: suggestion.kind == .slashCommand ? "slash.circle" : "doc.text")
                            .font(.ps(10, weight: .semibold))
                            .foregroundStyle(PrismTheme.accentSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .font(.ps(11, weight: .semibold))
                                .foregroundStyle(PrismTheme.textPrimary)
                            if let detail = suggestion.detail {
                                Text(detail)
                                    .font(.ps(9))
                                    .foregroundStyle(PrismTheme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PrismHandButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PrismTheme.surfaceElevated)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PrismTheme.borderSubtle, lineWidth: 1)
        )
    }
}
