import SwiftUI

/// Assistant bubble content with Murmura-style reasoning card + answer body.
struct CoworkAssistantMessageContent: View {
    let msgID: String?
    let rawText: String
    let isStreaming: Bool
    var segment: CoworkLiveStreamSegment?
    var supportsImplicitLeadingThinking: Bool = false
    var onPersistThinkingExpanded: (Bool) -> Void = { _ in }

    private var parsed: (answer: String, thinking: String) {
        if let segment, isStreaming {
            return (segment.answer, segment.thinking)
        }
        return CoworkThinkingTagStreamParser.split(
            rawText,
            supportsImplicitLeadingThinking: supportsImplicitLeadingThinking
        )
    }

    private var thinkingText: String {
        parsed.thinking.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var answerText: String {
        parsed.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isThinkingActive: Bool {
        if let segment, isStreaming {
            return segment.isThinkingActive
        }
        return false
    }

    private var thinkingFinishedAt: Date? {
        segment?.thinkingFinishedAt
    }

    private var persistedExpanded: Bool? {
        segment?.thinkingCardExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !thinkingText.isEmpty {
                CoworkThinkingCard(
                    text: thinkingText,
                    isThinking: isThinkingActive,
                    collapseAfter: thinkingFinishedAt,
                    persistedExpanded: persistedExpanded,
                    onPersistExpanded: onPersistThinkingExpanded
                )
            }

            if answerText.isEmpty && isStreaming && thinkingText.isEmpty {
                CoworkWaitingWaveform()
            } else if !answerText.isEmpty {
                CoworkMarkdownMessageText(source: answerText, baseSize: 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PrismTheme.surfaceMuted.opacity(0.65))
        )
    }
}
