import SwiftUI

/// BYOK output token limits (Aisance `ai-models-cost-control-settings`).
struct CoworkBYOKCostControlView: View {
    @EnvironmentObject var cowork: CoworkState

    @State private var settings = CoworkBYOKTokenLimitsStore.load()
    @State private var defaultTokens = ""
    @State private var modelCaps: [String: String] = [:]
    @State private var modelEnabled: [String: Bool] = [:]
    @State private var isSaving = false
    @State private var savedFlash = false

    private var detectedModels: [String] { cowork.enabledCloudModelIDs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                howItWorks
                defaultField
                modelsSection
                saveButton
            }
            .padding(20)
        }
        .onAppear { hydrateFromSettings() }
        .onChange(of: cowork.enabledCloudModelIDs) { _ in hydrateFromSettings() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.costControlTitle)
                .font(.ps(16, weight: .bold, design: .rounded))
            Text(L10n.costControlSubtitle)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.costControlHowTitle)
                .font(.ps(11, weight: .semibold))
            Text(L10n.costControlHowBody)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PrismTheme.surfaceMuted.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var defaultField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.costControlDefaultLabel, systemImage: "questionmark.circle")
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
            TextField(L10n.costControlDefaultPlaceholder, text: $defaultTokens)
                .textFieldStyle(.roundedBorder)
                .font(.ps(12))
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.costControlDetectedLabel)
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)

            if detectedModels.isEmpty {
                Text(L10n.costControlNoModels)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PrismTheme.surfaceMuted.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(detectedModels, id: \.self) { modelID in
                    modelRow(modelID)
                }
            }
        }
    }

    private func modelRow(_ modelID: String) -> some View {
        let enabled = modelEnabled[modelID] ?? false
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { modelEnabled[modelID] ?? false },
                set: { modelEnabled[modelID] = $0 }
            ))
            .labelsHidden()
            .toggleStyle(PrismHandToggleStyle(kind: .checkbox))

            Text(modelID)
                .font(.ps(9, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(L10n.costControlCapPlaceholder, text: Binding(
                get: { modelCaps[modelID] ?? "" },
                set: { modelCaps[modelID] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.ps(10))
            .frame(width: 72)
            .disabled(!enabled)

            Button(L10n.costControlFast) {
                let caps = CoworkBYOKTokenLimitsStore.recommendedCaps(for: modelID)
                modelCaps[modelID] = "\(caps.fast)"
                modelEnabled[modelID] = true
            }
            .font(.ps(9, weight: .semibold))
            .disabled(!enabled)

            Button(L10n.costControlSafe) {
                let caps = CoworkBYOKTokenLimitsStore.recommendedCaps(for: modelID)
                modelCaps[modelID] = "\(caps.safe)"
                modelEnabled[modelID] = true
            }
            .font(.ps(9, weight: .semibold))
            .disabled(!enabled)
        }
        .padding(8)
        .background(PrismTheme.surfaceMuted.opacity(enabled ? 0.35 : 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else if savedFlash {
                    Image(systemName: "checkmark")
                }
                Text(isSaving ? L10n.savingEllipsis : L10n.costControlSave)
            }
        }
        .disabled(isSaving)
    }

    private func hydrateFromSettings() {
        if let def = settings.maxOutputTokensDefault {
            defaultTokens = "\(def)"
        }
        for model in detectedModels {
            if let cap = settings.maxOutputTokensByModel[model] {
                modelCaps[model] = "\(cap)"
                modelEnabled[model] = true
            } else {
                modelCaps[model] = modelCaps[model] ?? ""
                modelEnabled[model] = modelEnabled[model] ?? false
            }
        }
    }

    private func save() async {
        isSaving = true
        savedFlash = false
        defer { isSaving = false }

        let defaultCap = Int(defaultTokens.trimmingCharacters(in: .whitespacesAndNewlines))
        var byModel: [String: Int] = [:]
        for model in detectedModels where modelEnabled[model] == true {
            if let val = Int(modelCaps[model] ?? ""), val > 0 {
                byModel[model] = val
            }
        }
        // Preserve caps for models not currently listed.
        for (model, cap) in settings.maxOutputTokensByModel where !detectedModels.contains(model) && cap > 0 {
            byModel[model] = cap
        }

        let next = CoworkBYOKTokenLimitsSettings(
            maxOutputTokensDefault: (defaultCap ?? 0) > 0 ? defaultCap : nil,
            maxOutputTokensByModel: byModel
        )
        CoworkBYOKTokenLimitsStore.save(next)
        settings = next
        savedFlash = true
    }
}
