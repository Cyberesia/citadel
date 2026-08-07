import SwiftUI

/// Mid-chat model switcher — MLX, Ollama, and cloud providers in one menu.
struct CoworkSessionModelMenu: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        Menu {
            if !cowork.mlxInstalledModels.isEmpty {
                Section("Native MLX (on-device)") {
                    Text(L10n.mlxChatOnlyHint)
                        .font(.ps(9))
                        .foregroundStyle(.secondary)
                    ForEach(cowork.mlxInstalledModels, id: \.id) { model in
                        Button {
                            Task { await cowork.switchActiveConversationToMLX(model.id) }
                        } label: {
                            menuRow(
                                title: model.displayName,
                                subtitle: model.id,
                                isCurrent: isCurrent(model: model.id)
                            )
                        }
                    }
                }
            }

            if !cowork.ollamaChatModels.isEmpty {
                Section("Ollama (local)") {
                    ForEach(cowork.ollamaChatModels) { model in
                        Button {
                            Task {
                                await cowork.selectOllamaModel(model.name)
                                if let providerID = cowork.selectedProviderID {
                                    await cowork.switchActiveConversationModel(providerID: providerID, model: model.name)
                                }
                            }
                        } label: {
                            menuRow(
                                title: CoworkUserFacing.modelLabel(providerID: nil, rawModel: model.name),
                                subtitle: model.name,
                                isCurrent: isCurrent(model: model.name)
                            )
                        }
                    }
                }
            }

            ForEach(cloudProviders, id: \.id) { provider in
                Section(CoworkUserFacing.providerLabel(platform: provider.platform, name: provider.name, providerID: provider.id)) {
                    ForEach(provider.models, id: \.self) { model in
                        Button {
                            Task { await cowork.selectCloudModel(providerID: provider.id, model: model) }
                        } label: {
                            menuRow(
                                title: CoworkUserFacing.modelLabel(providerID: provider.id, rawModel: model),
                                subtitle: model,
                                isCurrent: isCurrent(model: model)
                            )
                        }
                    }
                }
            }

            Divider()
            Button(L10n.manageProviders) {
                DispatchQueue.main.async {
                    cowork.showProvidersManager = true
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.ps(9, weight: .semibold))
                CoworkModelBadge(display: cowork.activeModelDisplay, compact: true)
                Image(systemName: "chevron.down")
                    .font(.ps(7, weight: .bold))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PrismTheme.surfaceMuted.opacity(0.5))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch the model for this session")
        .onAppear {
            Task { await cowork.refreshOllamaModels() }
            cowork.refreshMLXModels()
        }
    }

    /// Providers that aren't the local Ollama/MLX endpoints already shown above.
    private var cloudProviders: [CoworkProvider] {
        cowork.providers.filter { provider in
            let base = provider.baseURL.lowercased()
            let isLocal = base.contains("127.0.0.1") || base.contains("localhost")
            return !isLocal && !provider.models.isEmpty && provider.enabled != false
        }
    }

    private func isCurrent(model: String) -> Bool {
        if let conversationModel = cowork.activeConversation?.model?.model {
            return conversationModel == model
        }
        return cowork.selectedModelID == model
    }

    @ViewBuilder
    private func menuRow(title: String, subtitle: String, isCurrent: Bool) -> some View {
        if isCurrent {
            Label("\(title) — \(subtitle)", systemImage: "checkmark")
        } else {
            Text("\(title) — \(subtitle)")
        }
    }
}
