import SwiftUI

/// Murmura-style model picker: Ollama, MLX, and BYOK cloud providers in one popover.
struct CoworkModelPicker: View {
    @EnvironmentObject var cowork: CoworkState
    @AppStorage("cowork.modelPickerTab") private var tabRaw = CoworkModelPickerTab.ollama.rawValue
    @AppStorage("cowork.selectedMLXRepoID") private var selectedMLXRepoID = ""
    @State private var showPopover = false

    private var activeTab: CoworkModelPickerTab {
        CoworkModelPickerTab(rawValue: tabRaw) ?? .ollama
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .help(statusHelp)

            Button { showPopover.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: tabIcon)
                        .font(.ps(12, weight: .semibold))
                    CoworkModelBadge(display: currentModelDisplay)
                    Image(systemName: "chevron.down")
                        .font(.ps(9, weight: .bold))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                .foregroundStyle(PrismTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(PrismTheme.surfaceMuted.opacity(0.75))
                        .overlay(Capsule(style: .continuous).stroke(PrismTheme.textTertiary.opacity(0.25), lineWidth: 1))
                )
            }
            .buttonStyle(PrismHandButtonStyle())
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                pickerContent
                    .prismPopoverChrome(width: 340, maxHeight: 360)
            }
            .onAppear {
                Task {
                    await cowork.refreshOllamaModels()
                    await cowork.refreshMLXModelsAsync()
                }
            }
            .onChange(of: cowork.selectedModelID) { _ in
                tabRaw = cowork.inferredModelPickerTab.rawValue
            }

            if cowork.isLoadingOllamaModels {
                ProgressView().controlSize(.small)
            }

            Spacer()
        }
    }

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabSegment

            switch activeTab {
            case .ollama:
                ollamaList
            case .mlx:
                mlxList
            case .cloud:
                cloudList
            }

            Divider().opacity(0.2)

            Button {
                Task {
                    await cowork.refreshOllamaModels()
                    await cowork.repairProviders()
                }
            } label: {
                Label(L10n.refreshModels, systemImage: "arrow.clockwise")
                    .font(.ps(11))
            }
            .buttonStyle(PrismHandButtonStyle())

            Button(L10n.manageProviders) {
                showPopover = false
                DispatchQueue.main.async {
                    cowork.showProvidersManager = true
                }
            }
            .buttonStyle(PrismHandButtonStyle())
            .font(.ps(11))
        }
        .onAppear {
            tabRaw = cowork.inferredModelPickerTab.rawValue
        }
    }

    private var tabSegment: some View {
        HStack(spacing: 2) {
            ForEach(CoworkModelPickerTab.allCases) { item in
                Button {
                    tabRaw = item.rawValue
                    switch item {
                    case .mlx:
                        let repo = selectedMLXRepoID.isEmpty
                            ? CoworkMLXModelCatalog.defaultRepoID
                            : selectedMLXRepoID
                        Task { _ = await cowork.selectMLXModel(repo) }
                    case .ollama:
                        if let model = cowork.selectedModelID ?? cowork.ollamaChatModels.first?.name {
                            Task { await cowork.selectOllamaModel(model) }
                        }
                    case .cloud:
                        if let provider = cowork.cloudProviders.first(where: { ($0.enabled ?? true) && !$0.models.isEmpty }),
                           let model = provider.models.first {
                            Task { await cowork.selectCloudModel(providerID: provider.id, model: model) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.iconName)
                            .font(.ps(8, weight: .semibold))
                        Text(item.label)
                            .font(.ps(9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(activeTab == item ? PrismTheme.textPrimary : PrismTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(activeTab == item ? PrismTheme.accentSoft : Color.clear)
                    )
                }
                .buttonStyle(PrismHandButtonStyle())
            }
        }
        .padding(3)
        .background(PrismTheme.surfaceMuted.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var ollamaList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if cowork.ollamaChatModels.isEmpty && !cowork.isLoadingOllamaModels {
                    Text(cowork.ollamaReachable ? L10n.ollamaNoModels : L10n.ollamaNotReachable)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .padding(10)
                }
                ForEach(cowork.ollamaChatModels) { model in
                    modelRow(
                        alias: CoworkUserFacing.modelDisplay(
                            providerID: cowork.selectedProviderID,
                            rawModel: model.name,
                            providers: cowork.providers
                        ).alias,
                        summary: model.name,
                        isSelected: isOllamaSelected(model.name),
                        chatOnly: !model.supportsTools
                    ) {
                        selectOllamaModel(model.name)
                        showPopover = false
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private var mlxList: some View {
        CoworkMLXModelManagerContent {
            showPopover = false
        }
        .onAppear {
            CoworkMLXModelLibrary.shared.refreshInstalledByteSizes()
            cowork.refreshMLXModels()
        }
    }

    private var cloudList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if cowork.cloudProviders.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.noCloudProviders)
                            .font(.ps(11, weight: .semibold))
                        Text(L10n.noCloudProvidersDetail)
                            .font(.ps(10))
                            .foregroundStyle(PrismTheme.textSecondary)
                        Button(L10n.addModelProvider) {
                            showPopover = false
                            DispatchQueue.main.async {
                                cowork.showProviderSheet = true
                            }
                        }
                        .font(.ps(10, weight: .semibold))
                        .buttonStyle(PrismHandButtonStyle())
                    }
                    .padding(10)
                } else {
                    ForEach(cowork.cloudProviders) { provider in
                        if provider.enabled != false, !provider.models.isEmpty {
                            cloudProviderSection(provider)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func cloudProviderSection(_ provider: CoworkProvider) -> some View {
        let preset = CoworkProviderPreset.from(platform: provider.platform)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: preset.iconName)
                    .font(.ps(9, weight: .semibold))
                    .foregroundStyle(PrismTheme.accent)
                Text(CoworkUserFacing.providerLabel(platform: provider.platform, name: provider.name, providerID: provider.id))
                    .font(.ps(10, weight: .bold))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            .padding(.horizontal, 6)

            ForEach(provider.models, id: \.self) { model in
                let enriched = CoworkCloudModelCatalog.enrich(
                    .named(id: model, name: CoworkUserFacing.modelLabel(providerID: provider.id, rawModel: model)),
                    platform: provider.platform
                )
                modelRow(
                    alias: enriched.name,
                    summary: model,
                    isSelected: isCloudSelected(providerID: provider.id, model: model),
                    chatOnly: false
                ) {
                    Task {
                        await cowork.selectCloudModel(providerID: provider.id, model: model)
                        showPopover = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(
        alias: String,
        summary: String,
        isSelected: Bool,
        chatOnly: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(alias)
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text(summary)
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if chatOnly {
                    Text(L10n.chatOnly)
                        .font(.ps(8, weight: .bold))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PrismTheme.surfaceMuted.opacity(0.6))
                        .clipShape(Capsule())
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.ps(10, weight: .bold))
                        .foregroundStyle(PrismTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismHandButtonStyle())
    }

    private var currentModelDisplay: CoworkUserFacing.ModelDisplay {
        if activeTab == .mlx || cowork.inferredModelPickerTab == .mlx {
            let repoID = selectedMLXRepoID.isEmpty
                ? (cowork.mlxInstalledModels.first?.id ?? CoworkMLXModelCatalog.defaultRepoID)
                : selectedMLXRepoID
            return CoworkUserFacing.modelDisplay(
                providerID: "mlx",
                rawModel: repoID,
                providers: cowork.providers
            )
        }
        if let model = cowork.selectedModelID {
            return CoworkUserFacing.modelDisplay(
                providerID: cowork.selectedProviderID,
                rawModel: model,
                providers: cowork.providers
            )
        }
        return CoworkUserFacing.ModelDisplay(
            alias: L10n.selectModel,
            technical: nil,
            provider: activeTab.label
        )
    }

    private var tabIcon: String {
        cowork.inferredModelPickerTab.iconName
    }

    private var statusColor: Color {
        switch cowork.inferredModelPickerTab {
        case .mlx:
            return cowork.mlxInstalledModels.isEmpty ? .orange : .green
        case .cloud:
            return cowork.cloudProviders.isEmpty ? .orange : .green
        case .ollama:
            return cowork.ollamaReachable ? .green : .red
        }
    }

    private var statusHelp: String {
        switch cowork.inferredModelPickerTab {
        case .mlx:
            return cowork.mlxInstalledModels.isEmpty ? "No MLX models on disk" : "MLX weights found"
        case .cloud:
            return cowork.cloudProviders.isEmpty ? L10n.noCloudProviders : L10n.cloudTab
        case .ollama:
            return cowork.ollamaReachable ? L10n.ollamaReachable : L10n.ollamaOffline
        }
    }

    private func isOllamaSelected(_ name: String) -> Bool {
        cowork.inferredModelPickerTab == .ollama && cowork.selectedModelID == name
    }

    private func isCloudSelected(providerID: String, model: String) -> Bool {
        cowork.selectedProviderID == providerID && cowork.selectedModelID == model
    }

    private func selectOllamaModel(_ name: String) {
        tabRaw = CoworkModelPickerTab.ollama.rawValue
        Task { await cowork.selectOllamaModel(name) }
    }
}
