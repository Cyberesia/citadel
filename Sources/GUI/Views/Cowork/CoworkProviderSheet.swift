import SwiftUI

struct CoworkProviderSheet: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss

    private enum Step { case credentials, models }

    @State private var step: Step = .credentials
    @State private var preset: CoworkProviderPreset = .openAI
    @State private var name = "OpenAI"
    @State private var baseURL = CoworkProviderPreset.openAI.defaultBaseURL
    @State private var apiKey = ""
    @State private var infomaniakProductId = ""
    @State private var discoveredBaseURL: String?
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        Group {
            switch step {
            case .credentials:
                credentialsStep
            case .models:
                CoworkCloudModelsManagerView(
                    preset: preset,
                    providerID: nil,
                    providerName: name,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    productId: preset == .infomaniak ? infomaniakProductId.nilIfEmpty : nil,
                    initialEnabled: [],
                    onSave: { models in
                        try await saveProvider(models: models)
                    }
                )
                .environmentObject(cowork)
            }
        }
        .onAppear { applyPreset(preset) }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.modelProviders)
                .font(.ps(18, weight: .bold, design: .rounded))
            Text(L10n.providersSubtitle)
                .font(.ps(12))
                .foregroundStyle(PrismTheme.textSecondary)

            providerPresetPicker

            field(L10n.assistantName, text: $name)
            field(L10n.baseURLLabel, text: $baseURL)
            if preset.isCloud {
                field(L10n.apiKeyLabel, text: $apiKey, secure: true)
            } else {
                field(L10n.apiKeyLabel, text: $apiKey, secure: true)
            }

            if preset == .infomaniak {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.infomaniakProductIdLabel)
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.textSecondary)
                    TextField(L10n.infomaniakProductIdPlaceholder, text: $infomaniakProductId)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.infomaniakProductIdHelp)
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.signalDeny)
            }

            HStack {
                Spacer()
                Button(L10n.cronCancel) { dismiss() }
                Button(preset.isCloud ? L10n.continueToModels : L10n.cronSave) {
                    Task {
                        if preset.isCloud {
                            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                errorText = L10n.apiKeyRequired
                                return
                            }
                            step = .models
                        } else {
                            await saveLocalProvider()
                        }
                    }
                }
                .disabled(isSaving || baseURL.isEmpty)
                .keyboardShortcut(.defaultAction)
            }

            if isSaving {
                PrismActivityBanner(icon: "key.fill", message: L10n.savingEllipsis, compact: true)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var providerPresetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.providerLabel)
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
            Text(L10n.cloudProvidersSection)
                .font(.ps(10, weight: .bold))
                .foregroundStyle(PrismTheme.textTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                ForEach(CoworkProviderPreset.cloudCases) { item in
                    providerPresetChip(item)
                }
            }
            Text(L10n.localProvidersSection)
                .font(.ps(10, weight: .bold))
                .foregroundStyle(PrismTheme.textTertiary)
                .padding(.top, 2)
            HStack(spacing: 8) {
                providerPresetChip(.ollama)
                providerPresetChip(.lmStudio)
            }
        }
    }

    private func providerPresetChip(_ item: CoworkProviderPreset) -> some View {
        let selected = preset == item
        return Button {
            preset = item
            applyPreset(item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(selected ? PrismTheme.accent : PrismTheme.textSecondary)
                    .frame(width: 16)
                Text(item.label)
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? PrismTheme.accentSoft : PrismTheme.surfaceMuted.opacity(0.42))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selected ? PrismTheme.accent.opacity(0.45) : PrismTheme.borderSubtle,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(PrismHandButtonStyle())
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
            if secure {
                SecureField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func applyPreset(_ preset: CoworkProviderPreset) {
        name = preset.label
        baseURL = preset.defaultBaseURL
        apiKey = preset.defaultAPIKeyPlaceholder
        errorText = nil
    }

    private func saveLocalProvider() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            let result = try await cowork.discoverModels(preset: preset, baseURL: baseURL, apiKey: apiKey)
            discoveredBaseURL = result.fixedBaseURL
            guard let modelID = result.models.first?.id else {
                errorText = L10n.noModelsFound
                return
            }
            try await cowork.saveProviderModels(
                providerID: nil,
                preset: preset,
                name: name,
                baseURL: baseURL,
                apiKey: apiKey,
                enabledModelIDs: [modelID],
                resolvedBaseURL: discoveredBaseURL
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveProvider(models: [String]) async throws {
        try await cowork.saveProviderModels(
            providerID: nil,
            preset: preset,
            name: name,
            baseURL: baseURL,
            apiKey: apiKey,
            enabledModelIDs: models,
            resolvedBaseURL: discoveredBaseURL,
            productId: preset == .infomaniak ? infomaniakProductId.nilIfEmpty : nil
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
