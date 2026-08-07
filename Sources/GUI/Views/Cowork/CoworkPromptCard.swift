import SwiftUI

struct CoworkPromptCard: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var dictationTextBase = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sessionConfigSection
            composerSection
            workspaceSection
            CoworkAttachmentBar(
                paths: cowork.attachmentPaths,
                indexedPaths: cowork.indexedAttachmentPaths,
                onRemove: { path in
                    cowork.removeAttachment(path, target: .home)
                },
                onPreview: { path in
                    cowork.previewLocalAttachment(path)
                }
            )
            CoworkComposerToolbar(target: .home)

            if let notice = cowork.toolsDisabledNotice {
                CoworkToolsDisabledBanner()
            }
        }
        .padding(16)
        .prismGlass(cornerRadius: 22, padding: 0)
    }

    private var sessionConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.session)
                .font(.ps(10, weight: .bold))
                .foregroundStyle(PrismTheme.textTertiary)

            HStack(spacing: 8) {
                CoworkAssistantPicker()
                CoworkModelPicker()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CoworkAgentModePicker()
                    CoworkSkillsPicker()
                    CoworkMcpPicker()
                }
            }
        }
    }

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.message)
                .font(.ps(10, weight: .bold))
                .foregroundStyle(PrismTheme.textTertiary)

            CoworkChatComposer(
                text: $cowork.promptText,
                placeholder: L10n.messagePlaceholder,
                isEnabled: canType,
                minHeight: 88,
                maxHeight: 180,
                focusRequest: cowork.composerFocusGeneration,
                onDropFileURLs: { urls in
                    let paths = urls.map(\.path)
                    cowork.attachmentPaths.append(contentsOf: paths)
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
                onSubmit: {
                    Task { await cowork.sendFromHome() }
                }
            )

            HStack(spacing: 8) {
                CoworkVoiceDictationButton {
                    Task { await toggleVoice() }
                }
                CoworkVoiceDictationStatus()
                Spacer()
            }
            .onChange(of: cowork.voiceScribe.partialText) { _, partial in
                guard cowork.voiceScribe.isListening else { return }
                cowork.promptText = CoworkState.appendDictationTranscript(
                    to: dictationTextBase,
                    transcript: partial
                )
            }
        }
    }

    @ViewBuilder
    private var workspaceSection: some View {
        if !cowork.workspacePath.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.workspaceFolder)
                    .font(.ps(10, weight: .bold))
                    .foregroundStyle(PrismTheme.textTertiary)
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(PrismTheme.accentSecondary)
                    Text(cowork.workspacePath)
                        .font(.ps(10))
                        .lineLimit(1)
                        .foregroundStyle(PrismTheme.textSecondary)
                    Spacer()
                    Button(L10n.removeWorkspace) { cowork.workspacePath = "" }
                        .buttonStyle(PrismHandButtonStyle())
                        .font(.ps(10))
                        .help(L10n.removeWorkspaceHelp)
                }
            }
        }
    }

    private var canType: Bool {
        !cowork.isSending
    }

    private func toggleVoice() async {
        if cowork.voiceScribe.isListening {
            let transcript = cowork.voiceScribe.stopAndGetTranscript()
            if transcript.isEmpty {
                cowork.statusMessage = cowork.voiceScribe.errorMessage ?? L10n.voiceTranscriptionEmpty
            } else {
                cowork.promptText = CoworkState.appendDictationTranscript(to: dictationTextBase, transcript: transcript)
            }
            dictationTextBase = ""
            return
        }
        dictationTextBase = cowork.promptText
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
            cowork.statusMessage = L10n.localizeError(error.localizedDescription)
        }
        if let err = cowork.voiceScribe.errorMessage {
            cowork.statusMessage = err
        }
    }
}
