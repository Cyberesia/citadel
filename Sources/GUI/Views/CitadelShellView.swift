import SwiftUI

/// Unified main window — Fortress (network) + Cowork. Classic Monitor UI is retired;
/// `AppState` remains the firewall control plane for helper / NE / alerts / Settings.
struct CitadelShellView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var cowork: CoworkState
    @EnvironmentObject var fortress: FortressViewModel
    @EnvironmentObject var router: CitadelShellRouter
    @AppStorage("citadel.locale") private var localeRaw = CitadelLocale.current.rawValue
    @State private var palette: ExtractedPalette = .defaultPalette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                LivingCanvas(palette: palette) {
                    VStack(spacing: 16) {
                        header
                        mainPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                if router.section == .fortress && router.fortressMode == .activity {
                    FortressSummaryBar(vm: fortress)
                        .environmentObject(state)
                        .zIndex(100)
                }
            }
            .onAppear {
                updatePalette()
            }
            .onChange(of: router.section) { _ in updatePalette() }
            .onChange(of: router.fortressMode) { _ in updatePalette() }
            .onChange(of: router.coworkMode) { mode in
                cowork.closeConversation()
                if mode != .teams {
                    cowork.closeTeam()
                }
                updatePalette()
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .prismGlobalInteraction()
        .preferredColorScheme(.dark)
        .tint(PrismTheme.accent)
        .id(state.fontScale)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Citadel")
                    .font(.ps(22, weight: .bold, design: .rounded))
                    .foregroundStyle(PrismTheme.textPrimary)
                Text(headerSubtitle)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            Spacer()
            CitadelShellNavBar(
                expandedSection: $router.section,
                fortressMode: $router.fortressMode,
                coworkMode: $router.coworkMode,
                onKeepHelp: router.section == .cowork ? {
                    cowork.keepHelpTopicID = contextualHelpTopic
                    cowork.showKeepHelp = true
                } : nil,
                onFortressHelp: router.section == .fortress ? {
                    state.fortressHelpTopicID = fortressHelpTopic
                    state.showFortressHelp = true
                } : nil
            )
        }
    }

    private var fortressHelpTopic: String {
        switch router.fortressMode {
        case .activity: return "fortress-what-is"
        case .suspects: return "fortress-suspects"
        case .history: return "fortress-history"
        case .rules: return "fortress-rules"
        case .settings: return "fortress-protection"
        }
    }

    private var contextualHelpTopic: String {
        switch router.coworkMode {
        case .home: return "ask-start"
        case .sessions: return "sessions"
        case .assistants: return "assistants"
        case .teams: return "teams"
        case .tools: return "tools-mcp"
        case .schedule: return "schedule"
        case .agents: return "agents-what"
        }
    }

    private var headerSubtitle: String {
        switch router.section {
        case .fortress:
            switch router.fortressMode {
            case .activity: return L10n.fortressNetworkActivity
            case .suspects: return L10n.fortressSuspectsTitle
            case .history: return L10n.fortressHistoryTitle
            case .rules: return L10n.fortressRulesTitle
            case .settings: return L10n.fortressSettingsTitle
            }
        case .cowork:
            switch router.coworkMode {
            case .home: return L10n.keepSubtitleAsk
            case .sessions: return "\(L10n.keep) · \(L10n.coworkSessions)"
            case .assistants: return "\(L10n.keep) · \(L10n.coworkAssistants)"
            case .teams: return "\(L10n.keep) · \(L10n.coworkTeams)"
            case .tools: return "\(L10n.keep) · \(L10n.coworkTools)"
            case .schedule: return "\(L10n.keep) · \(L10n.coworkSchedule)"
            case .agents: return "\(L10n.keep) · \(L10n.coworkAgents)"
            }
        }
    }

    @ViewBuilder
    private var mainPanel: some View {
        Group {
            switch router.section {
            case .fortress:
                fortressPanel
            case .cowork:
                coworkPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .prismGlass(cornerRadius: 28, padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var fortressPanel: some View {
        Group {
            switch router.fortressMode {
            case .activity:
                FortressShellView()
                    .environmentObject(fortress)
            case .suspects:
                FortressSuspectsView()
                    .environmentObject(fortress)
                    .environmentObject(state)
                    .environmentObject(router)
            case .history:
                FortressHistoryView()
                    .environmentObject(state)
            case .rules:
                FortressRulesView()
                    .environmentObject(fortress)
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $state.showFortressHelp) {
            FortressHelpView()
                .environmentObject(state)
                .environmentObject(router)
        }
    }

    @ViewBuilder
    private var coworkPanel: some View {
        Group {
            if let _ = cowork.activeConversationID {
                CoworkConversationView()
            } else {
                switch router.coworkMode {
                case .home:
                    CoworkHomeView()
                case .sessions:
                    CoworkSessionsView()
                case .teams:
                    CoworkTeamsView()
                case .assistants:
                    CoworkAssistantsView()
                case .tools:
                    CoworkMcpSettingsView()
                case .schedule:
                    CoworkScheduledTasksView()
                case .agents:
                    CoworkAgentSettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $cowork.showProviderSheet) {
            CoworkProviderSheet()
                .environmentObject(cowork)
        }
        .sheet(isPresented: $cowork.showProvidersManager) {
            CoworkProvidersManagerView()
                .environmentObject(cowork)
        }
        .sheet(isPresented: $cowork.showMcpSheet) {
            CoworkMcpSettingsView(isModal: true)
                .environmentObject(cowork)
                .frame(minWidth: 520, minHeight: 480)
        }
        .sheet(isPresented: $cowork.showKeepHelp) {
            KeepHelpView()
                .environmentObject(cowork)
                .environmentObject(router)
        }
    }

    private func updatePalette() {
        // Do not wrap in withAnimation — that also animates the fortress/Keep
        // panel swap and can leave Activity stuck at a half-height glass frame.
        switch router.section {
        case .cowork:
            palette = ExtractedPalette(
                primary: Color(red: 0.10, green: 0.08, blue: 0.20),
                secondary: PrismTheme.dominantMid,
                accent: Color(red: 0.55, green: 0.38, blue: 1.0)
            ).tempered(blend: 0.26)
        case .fortress:
            switch router.fortressMode {
            case .activity:
                palette = ExtractedPalette(
                    primary: Color(red: 0.14, green: 0.10, blue: 0.08),
                    secondary: PrismTheme.dominantMid,
                    accent: PrismTheme.accent
                ).tempered(blend: 0.24)
            case .suspects:
                palette = ExtractedPalette(
                    primary: Color(red: 0.16, green: 0.08, blue: 0.08),
                    secondary: PrismTheme.dominantMid,
                    accent: PrismTheme.signalDeny
                ).tempered(blend: 0.22)
            case .history:
                palette = ExtractedPalette(
                    primary: Color(red: 0.10, green: 0.11, blue: 0.14),
                    secondary: PrismTheme.dominantMid,
                    accent: PrismTheme.accentSecondary
                ).tempered(blend: 0.22)
            case .rules:
                palette = ExtractedPalette(
                    primary: Color(red: 0.18, green: 0.10, blue: 0.14),
                    secondary: PrismTheme.dominantMid,
                    accent: PrismTheme.accent
                ).tempered(blend: 0.24)
            case .settings:
                palette = ExtractedPalette(
                    primary: Color(red: 0.10, green: 0.12, blue: 0.16),
                    secondary: PrismTheme.surfaceMuted,
                    accent: PrismTheme.accentSecondary
                ).tempered(blend: 0.20)
            }
        }
    }
}
