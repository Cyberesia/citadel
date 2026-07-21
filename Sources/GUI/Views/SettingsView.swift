import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var doh = AppConstants.defaultDoHUpstream
    @State private var startAtLogin = true
    @State private var showAlertsOnAllSpaces = true
    @State private var isEditingFont = false
    @State private var draftScale: Double = 1.0
    @ObservedObject private var companion = CitadelDeskCompanionController.shared
    @State private var selectedLocale = CitadelLocale.current
    @State private var tab: SettingsTab = .general

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general, dns, blocklists, profiles, about
        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: return L10n.settingsGeneral
            case .dns: return L10n.settingsDNS
            case .blocklists: return L10n.settingsBlocklists
            case .profiles: return L10n.settingsProfiles
            case .about: return L10n.settingsAbout
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gear"
            case .dns: return "globe"
            case .blocklists: return "shield.lefthalf.filled"
            case .profiles: return "person.crop.circle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(PrismTheme.surfaceMuted.opacity(0.4))

            Divider().opacity(0.3)

            ScrollView {
                content
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .prismGlobalInteraction()
        .id(selectedLocale)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.sentinelSettings)
                .font(.ps(13, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.ps(12, weight: .semibold))
                            .frame(width: 16)
                        Text(item.label)
                            .font(.ps(12, weight: tab == item ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == item ? PrismTheme.textPrimary : PrismTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if tab == item {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(PrismTheme.accent.opacity(0.18))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PrismHandButtonStyle())
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: generalTab
        case .dns: dnsTab
        case .blocklists: blocklistsTab
        case .profiles: profilesTab
        case .about: aboutTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(L10n.settingsGeneral) {
                Toggle(L10n.launchAtLogin, isOn: $startAtLogin)
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                Toggle(L10n.showAlertsAllSpaces, isOn: $showAlertsOnAllSpaces)
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
            }

            settingsSection(L10n.mode) {
                Picker(L10n.defaultMode, selection: Binding(get: { state.mode }, set: { state.setMode($0) })) {
                    Text(L10n.alertMode).tag(AppMode.alert)
                    Text(L10n.silentAllow).tag(AppMode.silentAllow)
                    Text(L10n.silentDeny).tag(AppMode.silentDeny)
                }
            }

            settingsSection(L10n.appearance) {
                fontSizeControl
                Picker(L10n.language, selection: $selectedLocale) {
                    ForEach(CitadelLocale.allCases) { locale in
                        Text(locale.label).tag(locale)
                    }
                }
                .onChange(of: selectedLocale) { _, locale in
                    CitadelLocale.setCurrent(locale)
                }
            }

            settingsSection(L10n.deskCompanion) {
                Toggle(L10n.companionEnabled, isOn: companionEnabled)
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                Toggle(L10n.companionDnd, isOn: companionQuiet)
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                    .disabled(!companion.isEnabled)
            }

            settingsSection(L10n.menuBar) {
                Text(L10n.crestMenuBarHint)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.crestPinnedAppsHint)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var companionEnabled: Binding<Bool> {
        Binding(
            get: { companion.isEnabled },
            set: { companion.isEnabled = $0; companion.presentIfNeeded() }
        )
    }

    private var companionQuiet: Binding<Bool> {
        Binding(get: { companion.quietMode }, set: { companion.quietMode = $0 })
    }

    private var fontSizeControl: some View {
        let shown = isEditingFont ? draftScale : Double(state.fontScale)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.fontSize)
                Spacer()
                Text("\(Int((shown * 100).rounded()))%")
                    .foregroundStyle(PrismTheme.textSecondary)
                    .monospacedDigit()
                Button { state.fontScale = 1.0 } label: { Text(L10n.reset) }
                    .buttonStyle(.link)
                    .prismClickable()
                    .disabled(abs(state.fontScale - 1.0) < 0.001)
            }
            HStack(spacing: 10) {
                Text("A").font(.system(size: 11))
                Slider(
                    value: Binding(get: { shown }, set: { draftScale = $0 }),
                    in: Double(AppFontScale.minimum)...Double(AppFontScale.maximum),
                    step: 0.05,
                    onEditingChanged: { editing in
                        if editing {
                            draftScale = Double(state.fontScale)
                            isEditingFont = true
                        } else {
                            isEditingFont = false
                            state.fontScale = AppFontScale.clamp(CGFloat(draftScale))
                        }
                    }
                )
                .prismClickable()
                Text("A").font(.system(size: 20, weight: .semibold))
            }
            Text(L10n.fontScaleHint)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
        }
    }

    private var dnsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(L10n.dohUpstream) {
                TextField(L10n.dohURL, text: $doh)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { state.helper.remote?.setDoHUpstream(url: doh) { _, _ in } }
                Text(L10n.examples)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                Text("https://cloudflare-dns.com/dns-query").font(.ps(11, design: .monospaced))
                Text("https://dns.quad9.net/dns-query").font(.ps(11, design: .monospaced))
                Text("https://dns.google/dns-query").font(.ps(11, design: .monospaced))
            }
            settingsSection(L10n.localDNSProxy) {
                Toggle(L10n.useSystemDNS, isOn: .constant(true))
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                Text(L10n.localDNSHint)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
        }
    }

    private var blocklistsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.settingsBlocklists).font(.ps(15, weight: .semibold))
                Spacer()
                Button(L10n.refreshAll) { state.helper.refreshBlocklists() }
                    .buttonStyle(PrismHandButtonStyle())
            }
            ForEach(state.blocklists) { b in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { b.enabled },
                        set: { newValue in
                            state.helper.remote?.enableBlocklist(idString: b.id.uuidString, enabled: newValue) { _, _ in }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.name).font(.ps(13))
                        Text(b.url).font(.ps(10)).foregroundStyle(PrismTheme.textTertiary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(b.entryCount)").font(.ps(11).monospacedDigit())
                        .foregroundStyle(PrismTheme.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var profilesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.settingsProfiles).font(.ps(15, weight: .semibold))
            ForEach(state.profiles) { p in
                HStack {
                    Image(systemName: p.icon)
                    Text(p.name)
                    Spacer()
                    if p.isActive {
                        StatusChip(L10n.active, color: PrismTheme.signalAllow)
                    } else {
                        Button(L10n.activate) {
                            state.activeProfile = p.name
                        }
                        .buttonStyle(PrismHandButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.ps(64))
                .foregroundStyle(PrismTheme.accent)
            Text("Citadel").font(.ps(22, weight: .bold))
            Text("v\(AppConstants.version)").font(.ps(12)).foregroundStyle(PrismTheme.textSecondary)
            Text(L10n.aboutTagline)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
            Divider().padding(.vertical, 8)
            Text(L10n.aboutAttributions)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.textTertiary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PrismTheme.surface.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(PrismTheme.borderSubtle, lineWidth: 0.5)
            )
        }
    }
}
