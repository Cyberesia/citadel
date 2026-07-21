import SwiftUI

/// Icon + short label so actions are obvious without hovering for a tooltip.
struct CoworkComposerToolbar: View {
    @EnvironmentObject var cowork: CoworkState

    var target: CoworkState.AttachmentTarget = .home

    var body: some View {
        HStack(spacing: 8) {
            CoworkComposerAction(
                title: L10n.attach,
                systemImage: "paperclip",
                help: L10n.attachHelp
            ) {
                cowork.pickAttachments(target: target)
            }

            CoworkComposerAction(
                title: L10n.folder,
                systemImage: "folder.badge.plus",
                help: L10n.t(
                    "Let the agent read and write inside a folder on your Mac",
                    "Autoriser l’agent à lire et écrire dans un dossier sur votre Mac"
                )
            ) {
                cowork.pickWorkspaceFolder()
            }

            CoworkComposerAction(
                title: L10n.models,
                systemImage: "key.fill",
                help: L10n.t(
                    "Connect Ollama, MLX, OpenAI, Anthropic, or other model providers",
                    "Connecter Ollama, MLX, OpenAI, Anthropic ou d’autres fournisseurs"
                )
            ) {
                cowork.showProvidersManager = true
            }

            Spacer()

            if cowork.isSending {
                ProgressView().controlSize(.small)
            }

            sendButton
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        let hasText = !cowork.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let enabled = hasText && !cowork.isSending
        Button {
            Task {
                switch target {
                case .home: await cowork.sendFromHome()
                case .composer: break
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(L10n.send)
                    .font(.ps(11, weight: .bold))
                Image(systemName: "arrow.up")
                    .font(.ps(11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    enabled ? PrismTheme.accentGradient : LinearGradient(
                        colors: [PrismTheme.surfaceMuted, PrismTheme.surfaceMuted],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
        }
        .buttonStyle(PrismHandButtonStyle())
        .help("Send message (Return in the text field)")
    }
}

struct CoworkComposerAction: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.ps(13, weight: .semibold))
                Text(title)
                    .font(.ps(9, weight: .medium))
            }
            .foregroundStyle(PrismTheme.textSecondary)
            .frame(minWidth: 52)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismHandButtonStyle())
        .help(help)
    }
}
