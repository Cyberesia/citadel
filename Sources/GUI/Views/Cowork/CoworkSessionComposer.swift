import SwiftUI

/// Session chat composer with labeled controls.
struct CoworkSessionComposer: View {
    @EnvironmentObject var cowork: CoworkState
    @Binding var text: String
    @State private var dictationTextBase = ""

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
                VStack(alignment: .leading, spacing: 4) {
                    CoworkVoiceDictationButton {
                        Task { await toggleVoice() }
                    }
                    CoworkVoiceDictationStatus()
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
        .onChange(of: cowork.voiceScribe.partialText) { _, partial in
            guard cowork.voiceScribe.isListening else { return }
            text = CoworkState.appendDictationTranscript(to: dictationTextBase, transcript: partial)
        }
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
            let transcript = cowork.voiceScribe.stopAndGetTranscript()
            if transcript.isEmpty {
                cowork.statusMessage = cowork.voiceScribe.errorMessage ?? L10n.voiceTranscriptionEmpty
            } else {
                text = CoworkState.appendDictationTranscript(to: dictationTextBase, transcript: transcript)
            }
            dictationTextBase = ""
            return
        }
        dictationTextBase = text
        cowork.voiceScribe.armListeningUI()
        do {
            guard await cowork.voiceScribe.requestAuthorization() else {
                cowork.voiceScribe.stopListening()
                cowork.statusMessage = cowork.voiceScribe.errorMessage ?? L10n.voicePermissionDenied
                dictationTextBase = ""
                return
            }
            try await cowork.voiceScribe.startListening()
        } catch {
            cowork.voiceScribe.stopListening()
            dictationTextBase = ""
            cowork.statusMessage = error.localizedDescription
        }
        if let err = cowork.voiceScribe.errorMessage {
            cowork.statusMessage = err
        }
    }
}
