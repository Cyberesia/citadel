import SwiftUI

struct CoworkPromptCard: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sessionConfigSection
            composerSection
            workspaceSection
            CoworkAttachmentBar(paths: cowork.attachmentPaths) { path in
                cowork.removeAttachment(path, target: .home)
            }
            CoworkComposerToolbar(target: .home)

            if let notice = cowork.toolsDisabledNotice {
                CoworkInfoBanner(message: notice)
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
                    cowork.attachmentPaths.append(contentsOf: urls.map(\.path))
                },
                onSubmit: {
                    Task { await cowork.sendFromHome() }
                }
            )

            HStack(spacing: 8) {
                CoworkComposerAction(
                    title: L10n.voiceScribe,
                    systemImage: cowork.voiceScribe.isListening ? "mic.fill" : "mic",
                    help: L10n.voiceTapToSpeak
                ) {
                    Task { await toggleVoice() }
                }
                if cowork.voiceScribe.isListening {
                    Text(L10n.voiceListening)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.accentSecondary)
                } else if cowork.voiceScribe.isTranscribing {
                    Text(L10n.voiceTranscribing)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.accentSecondary)
                }
                Spacer()
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
            let transcript = await cowork.voiceScribe.stopAndTranscribe(client: cowork.client)
            if !transcript.isEmpty {
                cowork.promptText = transcript
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
            cowork.statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }
}
