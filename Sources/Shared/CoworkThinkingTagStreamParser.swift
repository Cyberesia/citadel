import Foundation

/// Splits model output into visible answer text vs chain-of-thought hidden in XML-style tags.
/// Handles Qwen / MLX variants: think and redacted_thinking tags.
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
        ("<\("think")>", "</\("think")>"),
        ("<think>", "</think>"),
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
                let closeTag = activeCloseTag ?? Self.tagPairs[0].close
                if let range = pending.range(of: closeTag, options: [.caseInsensitive]) {
                    thinking += String(pending[..<range.lowerBound])
                    pending.removeSubrange(..<range.upperBound)
                    mode = .answer
                    activeCloseTag = nil
                    didFinishThinking = true
                } else {
                    let keep = Self.trailingTagPrefixLength(in: pending, tags: [closeTag])
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
            if supportsImplicitLeadingThinking {
                return (pending, "")
            }
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
        var best: (Range<String.Index>, String)?
        for pair in tagPairs {
            if let range = text.range(of: pair.open, options: [.caseInsensitive]) {
                if best == nil || range.lowerBound < best!.0.lowerBound {
                    best = (range, pair.close)
                }
            }
        }
        return best
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
