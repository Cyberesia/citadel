import SwiftUI

struct CoworkVoiceDictationButton: View {
    @EnvironmentObject var cowork: CoworkState
    let action: () -> Void

    private var isListening: Bool { cowork.voiceScribe.isListening }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.ps(13, weight: .semibold))
                    .symbolEffect(.pulse, isActive: isListening)
                Text(L10n.voiceScribe)
                    .font(.ps(9, weight: .medium))
            }
            .foregroundStyle(isListening ? PrismTheme.signalDeny : PrismTheme.signalAllow)
            .frame(minWidth: 52)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isListening ? PrismTheme.signalDeny.opacity(0.16) : PrismTheme.signalAllow.opacity(0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isListening ? PrismTheme.signalDeny.opacity(0.65) : PrismTheme.signalAllow.opacity(0.45),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismHandButtonStyle())
        .help(isListening ? L10n.voiceTapToFinish : L10n.voiceTapToSpeak)
        .accessibilityLabel(L10n.voiceScribe)
        .accessibilityHint(isListening ? L10n.voiceTapToFinish : L10n.voiceTapToSpeak)
        .accessibilityAddTraits(isListening ? [.isSelected] : [])
    }
}

struct CoworkVoiceDictationStatus: View {
    @EnvironmentObject var cowork: CoworkState

    private var isListening: Bool { cowork.voiceScribe.isListening }

    var body: some View {
        Group {
            if isListening {
                Text(statusText)
                    .foregroundStyle(PrismTheme.signalDeny)
            } else {
                Text(L10n.voiceTapToSpeak)
                    .foregroundStyle(PrismTheme.textTertiary)
            }
        }
        .font(.ps(10))
        .lineLimit(2)
    }

    private var statusText: String {
        let partial = cowork.voiceScribe.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        return partial.isEmpty ? L10n.voiceTapToFinish : partial
    }
}
