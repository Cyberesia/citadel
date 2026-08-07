import SwiftUI
import AppKit

enum CoworkMessageSegment {
    case text(String)
    case image(String)
}

/// Rich chat bubble: markdown body, inline images, streaming support.
struct CoworkMessageBubble: View {
    var message: CoworkMessage?
    let text: String
    let isUser: Bool
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let chunk):
                        if !chunk.isEmpty {
                            CoworkMarkdownMessageText(source: chunk, baseSize: 12)
                        }
                    case .image(let src):
                        CoworkInlineImageView(source: src, cowork: cowork)
                    }
                }
                if text.isEmpty && !isUser && cowork.isStreaming {
                    Text("…")
                        .font(.ps(12))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? AnyShapeStyle(PrismTheme.accentGradient) : AnyShapeStyle(PrismTheme.surfaceMuted.opacity(0.65)))
            )
            if !isUser { Spacer(minLength: 24) }
        }
    }

    private var segments: [CoworkMessageSegment] {
        CoworkMessageSegmentParser.parse(text)
    }
}

enum CoworkMessageSegmentParser {
    private static let imagePattern = #"!\[[^\]]*\]\(([^)]+)\)"#

    static func parse(_ source: String) -> [CoworkMessageSegment] {
        guard let regex = try? NSRegularExpression(pattern: imagePattern) else {
            return source.isEmpty ? [] : [.text(source)]
        }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return source.isEmpty ? [] : [.text(source)]
        }

        var segments: [CoworkMessageSegment] = []
        var cursor = 0
        for match in matches {
            let range = match.range
            if range.location > cursor {
                let chunk = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(chunk))
                }
            }
            if match.numberOfRanges > 1 {
                let url = ns.substring(with: match.range(at: 1))
                segments.append(.image(url))
            }
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(tail))
            }
        }
        return segments
    }
}

struct CoworkInlineImageView: View {
    let source: String
    let cowork: CoworkState
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: source) { await load() }
    }

    private func load() async {
        if source.hasPrefix("data:image"), let comma = source.firstIndex(of: ",") {
            let b64 = String(source[source.index(after: comma)...])
            if let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
                image = img
                return
            }
        }
        if source.hasPrefix("http://") || source.hasPrefix("https://"),
           let url = URL(string: source),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let img = NSImage(data: data) {
            image = img
            return
        }
        if let b64 = try? await cowork.client?.readImageBase64(path: source, workspace: cowork.activeConversation?.workspacePath) {
            if let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
                image = img
            }
        }
    }
}
