import SwiftUI

/// User turn: document excerpt cards (indexed, shimmer while assistant thinks) + orange question bubble.
struct CoworkUserMessageContent: View {
    let text: String
    var isShimmering: Bool

    private var parsed: CoworkParsedUserMessage {
        CoworkDocumentContextParser.parse(text)
    }

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(parsed.excerpts) { excerpt in
                    CoworkDocumentExcerptCard(excerpt: excerpt, isShimmering: isShimmering)
                        .frame(maxWidth: 520, alignment: .trailing)
                }
                if !parsed.userText.isEmpty {
                    CoworkMessageBubble(message: nil, text: parsed.userText, isUser: true)
                }
            }
        }
    }
}
