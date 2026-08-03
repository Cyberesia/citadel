import SwiftUI

/// Aisance Polaris cloud-models-manager: search, refresh, multi-select, sliding info blade.
struct CoworkCloudModelsManagerView: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss

    let preset: CoworkProviderPreset
    let providerID: String?
    let providerName: String
    let baseURL: String
    let apiKey: String
    var productId: String?
    let initialEnabled: Set<String>
    let onSave: ([String]) async throws -> Void

    @State private var allModels: [CoworkDiscoveredModel] = []
    @State private var enabledModels = Set<String>()
    @State private var searchQuery = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var activeInfoModelID: String?
    @State private var isInfoPinned = false
    @State private var bladeSlidOut = false

    private let modalWidth: CGFloat = 720
    private let bladeWidth: CGFloat = 300

    private var filtered: [CoworkDiscoveredModel] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allModels }
        return allModels.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    private var activeInfoModel: CoworkDiscoveredModel? {
        guard let id = activeInfoModelID else { return nil }
        return allModels.first { $0.id == id }
    }

    private var modalShift: CGFloat {
        activeInfoModelID != nil ? min(bladeWidth / 2, 140) : 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if activeInfoModel != nil {
                bladePanel
                    .frame(width: bladeWidth)
                    .offset(x: bladeSlidOut ? bladeWidth + 8 : 0)
                    .opacity(bladeSlidOut ? 1 : 0)
                    .animation(.easeOut(duration: 0.28), value: bladeSlidOut)
            }

            mainPanel
                .frame(width: modalWidth, height: 560)
                .offset(x: -modalShift)
                .animation(.easeOut(duration: 0.28), value: modalShift)
        }
        .frame(width: modalWidth + (activeInfoModel != nil ? bladeWidth + 16 : 0), height: 560)
        .background(PrismTheme.surface)
        .onAppear {
            enabledModels = initialEnabled
            Task { await fetchModels() }
        }
        .onChange(of: activeInfoModelID) { id in
            if id != nil {
                bladeSlidOut = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    bladeSlidOut = true
                }
            } else {
                bladeSlidOut = false
                isInfoPinned = false
            }
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            toolbar
            Divider().opacity(0.2)
            content
            Divider().opacity(0.2)
            footer
        }
        .background(PrismTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PrismTheme.textTertiary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }

    private var bladePanel: some View {
        Group {
            if let model = activeInfoModel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        bladeSection(L10n.modelIDLabel) {
                            Text(model.id)
                                .font(.ps(10, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PrismTheme.surfaceMuted.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        if let description = model.description {
                            bladeSection(L10n.descriptionLabel) {
                                Text(description)
                                    .font(.ps(11))
                                    .foregroundStyle(PrismTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let ctx = model.contextLength {
                            bladeSection(L10n.contextWindow) {
                                Text(L10n.contextTokens(ctx))
                                    .font(.ps(12, weight: .semibold))
                            }
                        }
                        if let pricing = model.pricingSummary {
                            bladeSection(L10n.pricing) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pricing)
                                    if let input = model.inputPricePerMillion, let output = model.outputPricePerMillion {
                                        Text(L10n.pricingInputOutput(input, output))
                                            .font(.ps(10))
                                            .foregroundStyle(PrismTheme.textSecondary)
                                    }
                                }
                                .font(.ps(11))
                            }
                        }
                        bladeSection(L10n.providerLabel) {
                            Text(model.provider.capitalized)
                                .font(.ps(12, weight: .semibold))
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(PrismTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PrismTheme.accent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 4, y: 4)
    }

    private func bladeSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.ps(8, weight: .bold))
                .foregroundStyle(PrismTheme.textTertiary)
            content()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: preset.iconName)
                .font(.ps(22, weight: .semibold))
                .foregroundStyle(PrismTheme.accent)
                .frame(width: 48, height: 48)
                .background(PrismTheme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.cloudModelsTitle(providerName))
                    .font(.ps(16, weight: .bold, design: .rounded))
                Text(L10n.cloudModelsSubtitle)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
            }

            Spacer()

            Button { Task { await fetchModels() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PrismHandButtonStyle())
            .disabled(isLoading || apiKey.isEmpty)

            if let docs = CoworkCloudModelCatalog.docsURL(for: preset) {
                Link(destination: docs) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(PrismHandButtonStyle())
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(PrismHandButtonStyle())
        }
        .padding(20)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
                TextField(L10n.searchModels, text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.ps(12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(PrismTheme.surfaceMuted.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(L10n.enableAll) { enabledModels = Set(allModels.map(\.id)) }
                .font(.ps(11, weight: .semibold))
                .disabled(isLoading || allModels.isEmpty)

            Button(L10n.disableAll) { enabledModels = [] }
                .font(.ps(11, weight: .semibold))
                .disabled(isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.loadingModels)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorText {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.ps(28))
                    .foregroundStyle(PrismTheme.signalDeny)
                Text(L10n.modelsLoadFailed)
                    .font(.ps(13, weight: .semibold))
                Text(errorText)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.ps(24))
                    .foregroundStyle(PrismTheme.textTertiary)
                Text(L10n.noModelsFound)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(filtered) { model in
                        modelCard(model)
                    }
                }
                .padding(20)
            }
        }
    }

    private func modelCard(_ model: CoworkDiscoveredModel) -> some View {
        let isOn = enabledModels.contains(model.id)
        let isInfoActive = activeInfoModelID == model.id

        return Button {
            if isOn { enabledModels.remove(model.id) } else { enabledModels.insert(model.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.ps(16, weight: .semibold))
                    .foregroundStyle(isOn ? PrismTheme.accent : PrismTheme.textTertiary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(model.name)
                            .font(.ps(12, weight: .semibold))
                            .foregroundStyle(PrismTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        infoButton(for: model)
                    }
                    if let description = model.description {
                        Text(description)
                            .font(.ps(10))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        if let ctx = model.contextLength {
                            Text(L10n.contextTokens(ctx))
                                .font(.ps(9))
                                .foregroundStyle(PrismTheme.textTertiary)
                        }
                        if let pricing = model.pricingSummary {
                            Text(pricing)
                                .font(.ps(9))
                                .foregroundStyle(PrismTheme.textTertiary)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? PrismTheme.accent.opacity(0.1) : PrismTheme.surfaceMuted.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isInfoActive ? PrismTheme.accent.opacity(0.5) :
                                    (isOn ? PrismTheme.accent.opacity(0.35) : PrismTheme.textTertiary.opacity(0.15)),
                                lineWidth: isInfoActive ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func infoButton(for model: CoworkDiscoveredModel) -> some View {
        Button {
            if isInfoPinned && activeInfoModelID == model.id {
                isInfoPinned = false
                activeInfoModelID = nil
            } else {
                activeInfoModelID = model.id
                isInfoPinned = true
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.ps(13))
                .foregroundStyle(activeInfoModelID == model.id ? PrismTheme.accent : PrismTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && !isInfoPinned {
                activeInfoModelID = model.id
            } else if !hovering && !isInfoPinned && activeInfoModelID == model.id {
                activeInfoModelID = nil
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(L10n.modelsEnabledCount(enabledModels.count, allModels.count))
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
            Spacer()
            Button(L10n.cronCancel) { dismiss() }
            Button(isSaving ? L10n.savingEllipsis : L10n.saveSelection) {
                Task { await save() }
            }
            .disabled(isSaving || enabledModels.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func fetchModels() async {
        guard !apiKey.isEmpty else {
            errorText = L10n.apiKeyRequired
            return
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            if let providerID, let provider = cowork.providers.first(where: { $0.id == providerID }) {
                allModels = try await cowork.refreshCloudModels(for: provider)
            } else {
                let result = try await cowork.discoverCloudModels(
                    preset: preset,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    productId: productId
                )
                allModels = result.models
            }
            if enabledModels.isEmpty, let first = allModels.first?.id {
                enabledModels = [first]
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(Array(enabledModels).sorted())
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
