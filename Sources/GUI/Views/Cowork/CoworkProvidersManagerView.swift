import SwiftUI

/// Central BYOK provider list: models manager + cost control (Aisance Polaris).
struct CoworkProvidersManagerView: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable, Identifiable {
        case providers
        case costControl

        var id: String { rawValue }

        var label: String {
            switch self {
            case .providers: return L10n.modelProviders
            case .costControl: return L10n.costControlTitle
            }
        }

        var icon: String {
            switch self {
            case .providers: return "cloud.fill"
            case .costControl: return "dollarsign.circle"
            }
        }
    }

    @State private var tab: Tab = .providers
    @State private var showAddSheet = false
    @State private var modelsSheet: ModelsSheetContext?

    private struct ModelsSheetContext: Identifiable {
        let id: String
        let provider: CoworkProvider
        let preset: CoworkProviderPreset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar
            Divider().opacity(0.2)

            switch tab {
            case .providers:
                providersBody
            case .costControl:
                CoworkBYOKCostControlView()
                    .environmentObject(cowork)
            }

            Divider().opacity(0.2)
            footer
        }
        .frame(width: tab == .costControl ? 620 : 520, height: 520)
        .sheet(isPresented: $showAddSheet) {
            CoworkProviderSheet()
                .environmentObject(cowork)
        }
        .sheet(item: $modelsSheet) { ctx in
            CoworkCloudModelsManagerView(
                preset: ctx.preset,
                providerID: ctx.provider.id,
                providerName: ctx.provider.name,
                baseURL: ctx.provider.baseURL,
                apiKey: ctx.provider.apiKey,
                productId: CoworkProviderExtraConfigStore.productId(for: ctx.provider.id),
                initialEnabled: Set(ctx.provider.models),
                onSave: { models in
                    try await cowork.saveProviderModels(
                        providerID: ctx.provider.id,
                        preset: ctx.preset,
                        name: ctx.provider.name,
                        baseURL: ctx.provider.baseURL,
                        apiKey: ctx.provider.apiKey,
                        enabledModelIDs: models,
                        resolvedBaseURL: nil,
                        productId: CoworkProviderExtraConfigStore.productId(for: ctx.provider.id)
                    )
                }
            )
            .environmentObject(cowork)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.ps(10, weight: .semibold))
                        Text(item.label)
                            .font(.ps(10, weight: .semibold))
                    }
                    .foregroundStyle(tab == item ? PrismTheme.textPrimary : PrismTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == item ? PrismTheme.accentSoft : Color.clear)
                    )
                }
                .buttonStyle(PrismHandButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var providersBody: some View {
        if cowork.cloudProviders.isEmpty {
            emptyState
        } else {
            List {
                Section(L10n.cloudProvidersSection) {
                    ForEach(cowork.cloudProviders) { provider in
                        providerRow(provider)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.modelProviders)
                    .font(.ps(18, weight: .bold, design: .rounded))
                Text(tab == .providers ? L10n.providersHelp : L10n.costControlSubtitle)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(PrismHandButtonStyle())
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.ps(32))
                .foregroundStyle(PrismTheme.textTertiary)
            Text(L10n.noCloudProviders)
                .font(.ps(13, weight: .semibold))
            Text(L10n.noCloudProvidersDetail)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func providerRow(_ provider: CoworkProvider) -> some View {
        let preset = CoworkProviderPreset.from(platform: provider.platform)
        let enabled = provider.enabled ?? true
        return HStack(spacing: 12) {
            Image(systemName: preset.iconName)
                .font(.ps(14, weight: .semibold))
                .foregroundStyle(PrismTheme.accent)
                .frame(width: 32, height: 32)
                .background(PrismTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.ps(12, weight: .semibold))
                Text(L10n.modelsCount(provider.models.count))
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { on in Task { await cowork.toggleProviderEnabled(provider, enabled: on) } }
            ))
            .toggleStyle(PrismHandToggleStyle(kind: .switch))
            .labelsHidden()

            Button(L10n.manageModels) {
                modelsSheet = ModelsSheetContext(id: provider.id, provider: provider, preset: preset)
            }
            .font(.ps(10, weight: .semibold))

            Button(role: .destructive) {
                Task { await cowork.deleteProvider(provider.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(PrismHandButtonStyle())
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if tab == .providers {
                Button {
                    showAddSheet = true
                } label: {
                    Label(L10n.addModelProvider, systemImage: "plus")
                }
            }
            Spacer()
            Button(L10n.cronCancel) { dismiss() }
        }
        .padding(16)
    }
}
