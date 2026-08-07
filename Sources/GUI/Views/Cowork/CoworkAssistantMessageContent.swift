import SwiftUI

/// Assistant bubble content with Murmura-style reasoning card + answer body.
struct CoworkAssistantMessageContent: View {
    @EnvironmentObject private var cowork: CoworkState
    let msgID: String?
    let rawText: String
    let isStreaming: Bool
    var segment: CoworkLiveStreamSegment?
    var supportsImplicitLeadingThinking: Bool = false
    var onPersistThinkingExpanded: (Bool) -> Void = { _ in }

    /// Subscribe to throttled stream ticks (segments themselves are not @Published).
    private var streamTick: Int { cowork.streamTick }

    private var archivedThinking: CoworkArchivedThinking? {
        guard let msgID else { return nil }
        return cowork.archivedThinkingByMsgID[msgID]
    }

    private var liveSegment: CoworkLiveStreamSegment? {
        if let segment { return segment }
        guard let msgID else { return nil }
        return cowork.liveStreamSegments[msgID]
    }

    private var thinkingText: String {
        let live = liveSegment?.thinking.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !live.isEmpty { return live }
        if let archivedThinking { return archivedThinking.text }
        // Only parse think-tags from raw bodies — never implicit (that swallows plain replies).
        if rawTextContainsThinkTags {
            return CoworkThinkingTagStreamParser.split(rawText, supportsImplicitLeadingThinking: false)
                .thinking
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private var answerText: String {
        if let liveSegment {
            return liveSegment.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Persisted/direct-chat bodies are already the visible reply. Implicit leading thinking
        // must NOT run here — it was eating the entire answer into the thinking pane.
        if rawTextContainsThinkTags {
            return CoworkThinkingTagStreamParser.split(trimmed, supportsImplicitLeadingThinking: false)
                .answer
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private var rawTextContainsThinkTags: Bool {
        let lower = rawText.lowercased()
        return lower.contains("<think") || lower.contains("redacted_thinking") || lower.contains("end_of_thought")
    }

    private var isThinkingActive: Bool {
        liveSegment?.isThinkingActive == true
    }

    private var thinkingFinishedAt: Date? {
        liveSegment?.thinkingFinishedAt ?? archivedThinking?.finishedAt
    }

    private var persistedExpanded: Bool? {
        liveSegment?.thinkingCardExpanded ?? archivedThinking?.cardExpanded
    }

    var body: some View {
        let _ = streamTick
        VStack(alignment: .leading, spacing: 10) {
            if !thinkingText.isEmpty {
                CoworkThinkingCard(
                    text: thinkingText,
                    isThinking: isThinkingActive,
                    collapseAfter: thinkingFinishedAt,
                    persistedExpanded: persistedExpanded,
                    allowsAutoCollapse: !answerText.isEmpty,
                    onPersistExpanded: onPersistThinkingExpanded
                )
            }

            if answerText.isEmpty && isStreaming && thinkingText.isEmpty {
                CoworkWaitingWaveform()
            } else if !answerText.isEmpty {
                CoworkMarkdownMessageText(source: answerText, baseSize: 12)
            } else if isStreaming && !isThinkingActive && thinkingText.isEmpty {
                CoworkWaitingWaveform()
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
