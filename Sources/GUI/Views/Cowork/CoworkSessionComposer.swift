import SwiftUI

/// Session chat composer with labeled controls.
struct CoworkSessionComposer: View {
    @EnvironmentObject var cowork: CoworkState
    @Binding var text: String

    var body: some View {
        VStack(spacing: 8) {
            if !suggestions.isEmpty {
                HStack {
                    CoworkComposerSuggestionList(suggestions: suggestions) { pick in
                        text = CoworkComposerSuggestionEngine.apply(pick, to: text)
                        cowork.requestComposerFocus()
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            CoworkAttachmentBar(
                paths: cowork.composerAttachments,
                indexedPaths: cowork.indexedAttachmentPaths,
                onRemove: { path in
                    cowork.removeAttachment(path, target: .composer)
                },
                onPreview: { path in
                    cowork.previewLocalAttachment(path)
                }
            )

            HStack(alignment: .bottom, spacing: 10) {
                CoworkComposerAction(
                    title: L10n.voiceScribe,
                    systemImage: cowork.voiceScribe.isListening ? "mic.fill" : "mic",
                    help: L10n.voiceTapToSpeak
                ) {
                    Task { await toggleVoice() }
                }

                CoworkComposerAction(
                    title: L10n.attach,
                    systemImage: "paperclip",
                    help: L10n.attachHelp
                ) {
                    cowork.pickAttachments(target: .composer)
                }

                CoworkChatComposer(
                    text: $text,
                    placeholder: L10n.replyPlaceholder,
                    isEnabled: !cowork.isSending && cowork.coreStatus == .running,
                    minHeight: 36,
                    maxHeight: 88,
                    focusRequest: cowork.composerFocusGeneration,
                    onDropFileURLs: { urls in
                        let paths = urls.map(\.path)
                        cowork.composerAttachments.append(contentsOf: paths)
                        if let last = paths.last {
                            cowork.previewLocalAttachment(last)
                        }
                        for path in paths {
                            let url = URL(fileURLWithPath: path)
                            if CoworkDocumentTextExtractor.extractText(from: url) != nil {
                                cowork.indexedAttachmentPaths.insert(path)
                            }
                        }
                    },
                    onSubmit: send
                )
                .frame(maxWidth: .infinity)

                Button(action: send) {
                    HStack(spacing: 4) {
                        Text(L10n.send)
                            .font(.ps(10, weight: .bold))
                        Image(systemName: "arrow.up")
                            .font(.ps(10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(canSend ? PrismTheme.accentGradient : LinearGradient(
                        colors: [PrismTheme.surfaceMuted, PrismTheme.surfaceMuted],
                        startPoint: .top, endPoint: .bottom
                    )))
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(!canSend)
                .help(L10n.sendHelp)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(PrismTheme.surfaceMuted.opacity(0.35))
    }

    private var suggestions: [CoworkComposerSuggestion] {
        CoworkComposerSuggestionEngine.suggestions(
            for: text,
            slashCommands: cowork.slashCommands,
            workspaceEntries: cowork.workspaceEntries
        )
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !cowork.isSending
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !cowork.isSending else { return }
        text = ""
        Task { await cowork.sendInConversation(trimmed) }
    }

    private func toggleVoice() async {
        if cowork.voiceScribe.isListening {
            let transcript = await cowork.voiceScribe.stopAndTranscribe(client: cowork.client)
            if !transcript.isEmpty {
                text = transcript
            }
            return
        }
        guard await cowork.voiceScribe.requestAuthorization() else {
            cowork.statusMessage = L10n.voicePermissionDenied
            return
        }
        do {
            try cowork.voiceScribe.startListening()
        } catch {
            cowork.statusMessage = error.localizedDescription
        }
    }
}
