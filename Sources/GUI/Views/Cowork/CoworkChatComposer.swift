import AppKit
import SwiftUI

/// Prism-styled chat composer — orange caret, placeholder hidden while typing.
struct CoworkChatComposer: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFocused = false

    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool = true
    var minHeight: CGFloat = 36
    var maxHeight: CGFloat = 96
    var focusRequest: Int = 0
    var onDropFileURLs: ([URL]) -> Void = { _ in }
    var onSubmit: () -> Void

    private var composerFont: NSFont {
        NSFont.systemFont(ofSize: 13)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MultilineChatComposer(
                text: $text,
                font: composerFont,
                isEnabled: isEnabled,
                colorScheme: colorScheme,
                caretColor: .prismAccentCaret,
                selectionColor: NSColor.prismAccentCaret.withAlphaComponent(0.22),
                focusRequest: focusRequest,
                onFocusChange: { isFocused = $0 },
                onDropFileURLs: onDropFileURLs,
                onSubmit: onSubmit
            )
            .frame(minHeight: minHeight, maxHeight: maxHeight)

            if text.isEmpty && !isFocused {
                Text(placeholder)
                    .font(.ps(13))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .padding(.leading, 4)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }
        }
    }
}
