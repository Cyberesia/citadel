import SwiftUI

/// User turn: document excerpt cards (indexed, shimmer while assistant thinks) + orange question bubble.
struct CoworkUserMessageContent: View {
    let text: String
    var isShimmering: Bool

    @State private var showAllExcerpts = false

    private var parsed: CoworkParsedUserMessage {
        CoworkDocumentContextParser.parse(text)
    }

    private var shouldCompactExcerpts: Bool {
        parsed.excerpts.count > 2 && !isShimmering && !showAllExcerpts
    }

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            VStack(alignment: .trailing, spacing: 8) {
                if shouldCompactExcerpts {
                    compactExcerptSummary
                } else {
                    ForEach(parsed.excerpts) { excerpt in
                        CoworkDocumentExcerptCard(excerpt: excerpt, isShimmering: isShimmering)
                            .frame(maxWidth: 520, alignment: .trailing)
                    }
                }
                if !parsed.userText.isEmpty {
                    CoworkMessageBubble(message: nil, text: parsed.userText, isUser: true)
                }
            }
        }
    }

    private var compactExcerptSummary: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showAllExcerpts = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PrismTheme.accentSecondary)
                Text(L10n.documentsIndexedCount(parsed.excerpts.count))
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PrismTheme.surfaceMuted.opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }
}
