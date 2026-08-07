import Foundation

/// Splits model output into visible answer text vs chain-of-thought hidden in XML-style tags.
/// Handles Qwen / MLX / Ollama variants: `<think>`, `<redacted_thinking>`, and Murmura-wrapped thinking.
struct CoworkThinkingTagStreamParser {
    private var pending = ""
    private var mode: Mode = .answer
    private var canUseImplicitLeadingThinking: Bool
    private let supportsImplicitLeadingThinking: Bool
    private var activeCloseTag: String?

    private enum Mode {
        case answer
        case thinking
    }

    private static let tagPairs: [(open: String, close: String)] = [
        ("<think>", "</think>"),
        ("<redacted_thinking>", "</redacted_thinking>"),
        ("<|redacted_thinking|>", "<|end_of_thought|>"),
    ]

    init(supportsImplicitLeadingThinking: Bool = false) {
        self.supportsImplicitLeadingThinking = supportsImplicitLeadingThinking
        self.canUseImplicitLeadingThinking = supportsImplicitLeadingThinking
    }

    mutating func process(_ chunk: String) -> (
        answer: String,
        thinking: String,
        didStartThinking: Bool,
        didFinishThinking: Bool
    ) {
        pending += chunk
        var answer = ""
        var thinking = ""
        var didStartThinking = false
        var didFinishThinking = false

        while !pending.isEmpty {
            switch mode {
            case .answer:
                if let (openRange, closeTag) = Self.earliestOpenTag(in: pending) {
                    answer += String(pending[..<openRange.lowerBound])
                    pending.removeSubrange(..<openRange.upperBound)
                    mode = .thinking
                    activeCloseTag = closeTag
                    didStartThinking = true
                    canUseImplicitLeadingThinking = false
                } else if canUseImplicitLeadingThinking {
                    mode = .thinking
                    activeCloseTag = nil
                    didStartThinking = true
                    canUseImplicitLeadingThinking = false
                } else {
                    let keep = Self.trailingTagPrefixLength(in: pending, tags: Self.tagPairs.map(\.open))
                    let outputEnd = pending.index(pending.endIndex, offsetBy: -keep)
                    answer += String(pending[..<outputEnd])
                    pending.removeSubrange(..<outputEnd)
                    if !answer.isEmpty {
                        canUseImplicitLeadingThinking = false
                    }
                    break
                }

            case .thinking:
                let closeCandidates = activeCloseTag.map { [$0] } ?? Self.tagPairs.map(\.close)
                if let (closeRange, _) = Self.earliestTag(in: pending, tags: closeCandidates) {
                    thinking += String(pending[..<closeRange.lowerBound])
                    pending.removeSubrange(..<closeRange.upperBound)
                    mode = .answer
                    activeCloseTag = nil
                    didFinishThinking = true
                } else {
                    let keep = Self.trailingTagPrefixLength(in: pending, tags: closeCandidates)
                    let outputEnd = pending.index(pending.endIndex, offsetBy: -keep)
                    thinking += String(pending[..<outputEnd])
                    pending.removeSubrange(..<outputEnd)
                    break
                }
            }
        }

        return (answer, thinking, didStartThinking, didFinishThinking)
    }

    mutating func flush() -> (answer: String, thinking: String) {
        defer {
            pending = ""
            mode = .answer
            activeCloseTag = nil
        }
        switch mode {
        case .answer:
            return (pending, "")
        case .thinking:
            // Keep unfinished reasoning in the thinking pane (never dump it into the answer).
            return ("", pending)
        }
    }

    /// One-shot parse for persisted message bodies that may still contain thinking tags.
    static func split(
        _ text: String,
        supportsImplicitLeadingThinking: Bool = false
    ) -> (answer: String, thinking: String) {
        var parser = CoworkThinkingTagStreamParser(supportsImplicitLeadingThinking: supportsImplicitLeadingThinking)
        let processed = parser.process(text)
        let flushed = parser.flush()
        let answer = processed.answer + flushed.answer
        let thinking = processed.thinking + flushed.thinking
        return (
            answer.trimmingCharacters(in: .whitespacesAndNewlines),
            thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func earliestOpenTag(in text: String) -> (Range<String.Index>, String)? {
        guard let hit = earliestTag(in: text, tags: tagPairs.map(\.open)) else { return nil }
        let open = String(text[hit.range])
        let close = tagPairs.first(where: { $0.open.compare(open, options: .caseInsensitive) == .orderedSame })?.close
            ?? tagPairs[0].close
        return (hit.range, close)
    }

    private static func earliestTag(in text: String, tags: [String]) -> (range: Range<String.Index>, tag: String)? {
        var best: (Range<String.Index>, String)?
        for tag in tags {
            if let range = text.range(of: tag, options: [.caseInsensitive]) {
                if best == nil || range.lowerBound < best!.0.lowerBound {
                    best = (range, tag)
                }
            }
        }
        return best.map { (range: $0.0, tag: $0.1) }
    }

    private static func trailingTagPrefixLength(in text: String, tags: [String]) -> Int {
        let lowerText = text.lowercased()
        var maxLength = 0
        for tag in tags {
            let lowerTag = tag.lowercased()
            let limit = min(lowerText.count, lowerTag.count - 1)
            guard limit > 0 else { continue }
            for length in stride(from: limit, through: 1, by: -1) {
                if lowerText.suffix(length) == lowerTag.prefix(length) {
                    maxLength = max(maxLength, length)
                    break
                }
            }
        }
        return maxLength
    }
}

struct CoworkLiveStreamSegment: Equatable {
    var answer: String = ""
    var thinking: String = ""
    var isThinkingActive = false
    var thinkingFinishedAt: Date?
    var thinkingCardExpanded: Bool?
}

/// Reasoning preserved after stream finish so the card can collapse instead of vanishing.
struct CoworkArchivedThinking: Equatable {
    var text: String
    var finishedAt: Date
    var cardExpanded: Bool?
}
