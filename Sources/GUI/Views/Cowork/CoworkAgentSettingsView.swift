import SwiftUI

struct CoworkAgentSettingsView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var showConnect = false
    @State private var customName = ""
    @State private var customCommand = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let status = cowork.statusMessage, !status.isEmpty {
                    statusBanner(status)
                }
                agentsSection
                CoworkRemoteSection()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { Task { await cowork.refreshManagedAgents() } }
        .sheet(isPresented: $showConnect) { connectSheet }
    }

    private func statusBanner(_ status: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(PrismTheme.accentSecondary)
            Text(status)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                cowork.statusMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.ps(9, weight: .semibold))
            }
            .buttonStyle(PrismHandButtonStyle())
        }
        .padding(10)
        .background(PrismTheme.surfaceMuted.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.coworkAgents)
                    .font(.ps(18, weight: .bold))
                Button {
                    cowork.keepHelpTopicID = "agents-what"
                    cowork.showKeepHelp = true
                } label: {
                    Label(L10n.keepHelpShort, systemImage: "book.closed.fill")
                        .font(.ps(11, weight: .medium))
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(PrismHandButtonStyle())
                .help(L10n.keepHelpTitle)
                Spacer()
                Button {
                    Task { await cowork.rescanInstalledAgents() }
                } label: {
                    HStack(spacing: 4) {
                        if cowork.isScanningAgents {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        Text(cowork.isScanningAgents ? L10n.scanningAgents : L10n.scanAgents)
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(cowork.isScanningAgents)
                Button(L10n.connectAgent) { showConnect = true }
                    .buttonStyle(PrismHandButtonStyle())
            }

            Text(L10n.agentsSubtitle)
                .font(.ps(12))
                .foregroundStyle(PrismTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            agentsAuthBanner

            if cowork.managedAgents.isEmpty {
                Text(L10n.agentsEmptyHint)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
            } else {
                ForEach(cowork.managedAgents) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    private var agentsAuthBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.accentSecondary)
                Text(L10n.agentsCLIAuthBanner)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if cowork.managedAgents.contains(where: { $0.id.lowercased().contains("claude") }) {
                Text(L10n.claudeSubscriptionNote)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(PrismTheme.surfaceMuted.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func agentRow(_ agent: CoworkManagedAgent) -> some View {
        let checking = cowork.checkingAgentIDs.contains(agent.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(agent.displayName).font(.ps(13, weight: .semibold))
                        statusCapsule(agent)
                    }
                    Text(KeepAgentBlurb.text(for: agent))
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(agent.subtitleLine)
                        .font(.ps(9, design: .monospaced))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .lineLimit(1)
                    if agent.isInstalled || agent.lastCheckErrorMessage != nil {
                        Text(agent.healthSummary)
                            .font(.ps(10))
                            .foregroundStyle(agent.isHealthy ? PrismTheme.signalAllow : PrismTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !agent.isHealthy, let guidance = agent.lastCheckGuidance, !guidance.isEmpty {
                        Text(guidance)
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { agent.enabled ?? true },
                        set: { on in Task { await cowork.setAgentEnabled(agent.id, enabled: on) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                    .help(L10n.agentEnabledHelp)

                    Button {
                        Task { await cowork.healthCheckAgent(agent.id) }
                    } label: {
                        HStack(spacing: 4) {
                            if checking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.seal")
                            }
                            Text(L10n.agentHealth)
                        }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(10))
                    .disabled(checking)
                }
            }
        }
        .padding(12)
        .background(PrismTheme.surfaceMuted.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusCapsule(_ agent: CoworkManagedAgent) -> some View {
        let installed = agent.isInstalled
        let label: String = {
            if !installed { return L10n.notInstalledBadge }
            switch agent.managementStatus {
            case "online": return L10n.agentStatusOnline
            case "offline": return L10n.agentStatusOffline
            case "missing": return L10n.agentStatusMissing
            default: return L10n.installedBadge
            }
        }()
        let color: Color = {
            if !installed { return PrismTheme.textTertiary }
            switch agent.managementStatus {
            case "online": return PrismTheme.signalAllow
            case "offline": return PrismTheme.signalDeny
            case "missing": return PrismTheme.textTertiary
            default: return PrismTheme.signalAllow.opacity(0.85)
            }
        }()
        return Text(label)
            .font(.ps(8, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var connectSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.connectAgent).font(.headline)
            Text(L10n.connectAgentHint)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
            TextField(L10n.assistantName, text: $customName)
            TextField(L10n.command, text: $customCommand)
            HStack {
                Button(L10n.testConnection) {
                    Task { _ = await cowork.tryConnectCustomAgent(name: customName, command: customCommand) }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(customCommand.isEmpty)
                Spacer()
                Button(L10n.cronCancel) { showConnect = false }.buttonStyle(PrismHandButtonStyle())
                Button(L10n.connect) {
                    Task {
                        await cowork.connectCustomAgent(name: customName, command: customCommand)
                        showConnect = false
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
            }
            if let status = cowork.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
