import SwiftUI

/// Settings for Fortress — general, DNS, blocklists, profiles, about.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var updates = CitadelUpdateController.shared
    @State private var doh = AppConstants.defaultDoHUpstream
    @ObservedObject private var companion = CitadelDeskCompanionController.shared
    @AppStorage("citadel.locale") private var localeRaw = CitadelLocale.current.rawValue

    private var localeBinding: Binding<CitadelLocale> {
        Binding(
            get: { CitadelLocale(rawValue: localeRaw) ?? .english },
            set: { localeRaw = $0.rawValue }
        )
    }
    @State private var tab: SettingsTab = .general
    @State private var isEditingFont = false
    @State private var draftScale: Double = 1.0

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
        .onAppear {
            state.refreshProfilesAndBlocklists()
            doh = UserDefaults.standard.string(forKey: "citadel.doh") ?? AppConstants.defaultDoHUpstream
            Task { await updates.checkIfNeeded() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.fortressSettings)
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
            settingsSection(L10n.protectionStatus) {
                Text(state.protectionStatusLabel)
                    .font(.ps(13, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Text(L10n.protectionHelp)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(L10n.askTimeoutDeny, isOn: Binding(
                    get: { state.askTimeoutDeny },
                    set: { state.setAskTimeoutDeny($0) }
                ))
                .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
            }

            settingsSection(L10n.settingsGeneral) {
                Toggle(L10n.launchAtLogin, isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                Toggle(L10n.showAlertsAllSpaces, isOn: Binding(
                    get: { state.showAlertsOnAllSpaces },
                    set: { state.setShowAlertsOnAllSpaces($0) }
                ))
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
                Picker(L10n.language, selection: localeBinding) {
                    ForEach(CitadelLocale.allCases) { locale in
                        Text(locale.label).tag(locale)
                    }
                }
                .onChange(of: localeRaw) { _, raw in
                    if let locale = CitadelLocale(rawValue: raw) {
                        CitadelLocale.setCurrent(locale)
                    }
                }
            }

            settingsSection(L10n.deskCompanion) {
                Toggle(L10n.companionEnabled, isOn: companionEnabled)
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                Toggle(L10n.companionDnd, isOn: companionQuiet)
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                    .disabled(!companion.isEnabled)
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
        }
    }

    private var dnsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(L10n.dohUpstream) {
                TextField(L10n.dohURL, text: $doh)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        UserDefaults.standard.set(doh, forKey: "citadel.doh")
                        state.helper.setDoHUpstream(doh)
                    }
                Text(L10n.localDNSHint)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            settingsSection(L10n.localDNSProxy) {
                Toggle(L10n.useSystemDNS, isOn: Binding(
                    get: { state.useSystemDNS },
                    set: { state.setUseSystemDNS($0) }
                ))
                .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                Text(L10n.dnsFilterExplain)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var blocklistsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.settingsBlocklists).font(.ps(15, weight: .semibold))
                Spacer()
                Button(L10n.refreshAll) {
                    state.helper.refreshBlocklists()
                    state.refreshProfilesAndBlocklists()
                }
                .buttonStyle(PrismHandButtonStyle())
            }
            Text(L10n.blocklistsExplain)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)

            if state.blocklists.isEmpty {
                Text(L10n.blocklistsEmpty)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textTertiary)
            }

            ForEach(state.blocklists) { b in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { b.enabled },
                        set: { newValue in
                            state.helper.enableBlocklist(id: b.id, enabled: newValue)
                            if var updated = state.blocklists.first(where: { $0.id == b.id }) {
                                updated.enabled = newValue
                                try? state.store?.updateBlocklist(updated)
                            }
                            state.refreshProfilesAndBlocklists()
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
            Text(L10n.profilesExplain)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
            ForEach(state.profiles) { p in
                HStack {
                    Image(systemName: p.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                        Text(modeLabel(p.mode))
                            .font(.ps(10))
                            .foregroundStyle(PrismTheme.textTertiary)
                    }
                    Spacer()
                    if p.isActive || state.activeProfile == p.name {
                        StatusChip(L10n.active, color: PrismTheme.signalAllow)
                    } else {
                        Button(L10n.activate) {
                            state.activateProfile(p.name)
                        }
                        .buttonStyle(PrismHandButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func modeLabel(_ mode: AppMode) -> String {
        switch mode {
        case .alert: return L10n.alertMode
        case .silentAllow: return L10n.silentAllow
        case .silentDeny: return L10n.silentDeny
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
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 8)
            updateSection
            Divider().padding(.vertical, 8)
            Text(L10n.aboutAttributions)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var updateSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if updates.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else if updates.updateAvailable {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(PrismTheme.accent)
                } else if updates.lastError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PrismTheme.signalAllow)
                }
                Text(updates.statusText)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(L10n.checkForUpdates) {
                    Task { await updates.check(force: true) }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(updates.isChecking)

                if updates.updateAvailable {
                    Button(L10n.downloadUpdate) {
                        updates.openDownloadPage()
                    }
                    .buttonStyle(PrismHandButtonStyle())
                }
            }
        }
        .frame(maxWidth: 360)
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
