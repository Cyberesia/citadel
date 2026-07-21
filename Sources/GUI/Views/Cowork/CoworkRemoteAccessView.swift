import SwiftUI
import AppKit

/// Phase 6: WebUI remote access (LAN + auth) and chat platform bridges (Telegram & co).
struct CoworkRemoteSection: View {
    @EnvironmentObject var cowork: CoworkState
    @EnvironmentObject var state: AppState
    @State private var tokenDrafts: [String: String] = [:]
    @State private var justCopied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            agentFirewallCard
            remoteAccessCard
            chatBridgesCard
        }
        .onAppear { Task { await cowork.refreshChannels() } }
    }

    // MARK: - Agent firewall (Citadel synergy)

    private var agentFirewallCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(PrismTheme.accent)
                Text(L10n.agentFirewall)
                    .font(.ps(14, weight: .semibold))
                Spacer()
            }

            Text(L10n.agentFirewallSubtitle)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textSecondary)

            Picker("", selection: Binding(
                get: { state.agentFirewallPolicy },
                set: { state.setAgentFirewallPolicy($0) }
            )) {
                Text(L10n.agentFirewallNoRule).tag(RuleAction?.none)
                Text(L10n.agentFirewallAllow).tag(RuleAction?.some(.allow))
                Text(L10n.agentFirewallAsk).tag(RuleAction?.some(.ask))
                Text(L10n.agentFirewallDeny).tag(RuleAction?.some(.deny))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .prismSegmentedControl()
        }
        .padding(14)
        .background(PrismTheme.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Remote access

    private var remoteAccessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(PrismTheme.accentSecondary)
                Text(L10n.remoteAccess)
                    .font(.ps(14, weight: .semibold))
                Spacer()
                if cowork.isRemoteBusy {
                    ProgressView().controlSize(.small)
                }
                Toggle("", isOn: Binding(
                    get: { cowork.remoteAccessEnabled },
                    set: { on in
                        Task {
                            if on { await cowork.enableRemoteAccess() }
                            else { await cowork.disableRemoteAccess() }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(PrismHandToggleStyle(kind: .switch))
                .disabled(cowork.isRemoteBusy)
            }

            Text(L10n.remoteAccessSubtitle)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textSecondary)

            if cowork.remoteAccessEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    if let url = cowork.remoteAccessURL {
                        infoRow(label: L10n.remoteURL, value: url, copyKey: "url")
                    }
                    if let user = cowork.remoteUsername, let pass = cowork.remotePassword {
                        infoRow(label: L10n.username, value: user, copyKey: "user")
                        infoRow(label: L10n.password, value: pass, copyKey: "pass", monospaced: true)
                    }
                    if let token = cowork.remoteQRToken {
                        HStack(spacing: 8) {
                            infoRow(label: L10n.remoteQR, value: token, copyKey: "qr", monospaced: true)
                            Button(L10n.remoteRegenerateQR) {
                                Task { await cowork.refreshQRToken() }
                            }
                            .buttonStyle(PrismHandButtonStyle())
                            .font(.ps(9))
                        }
                    }
                }
                .padding(10)
                .background(PrismTheme.surfaceMuted.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .background(PrismTheme.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoRow(label: String, value: String, copyKey: String, monospaced: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.ps(10, design: monospaced ? .monospaced : .default))
                .foregroundStyle(PrismTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                justCopied = copyKey
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if justCopied == copyKey { justCopied = nil }
                }
            } label: {
                Image(systemName: justCopied == copyKey ? "checkmark" : "doc.on.doc")
                    .font(.ps(9))
            }
            .buttonStyle(PrismHandButtonStyle())
            .help(justCopied == copyKey ? L10n.copied : L10n.copy)
        }
    }

    // MARK: - Chat bridges

    private var chatBridgesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "paperplane.circle.fill")
                    .foregroundStyle(PrismTheme.accentSecondary)
                Text(L10n.chatBridges)
                    .font(.ps(14, weight: .semibold))
                Spacer()
                Button {
                    Task { await cowork.refreshChannels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.ps(10))
                }
                .buttonStyle(PrismHandButtonStyle())
            }

            Text(L10n.chatBridgesSubtitle)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textSecondary)

            if cowork.channelPlugins.isEmpty {
                Text(L10n.chatBridgesEmpty)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
            }

            ForEach(cowork.channelPlugins) { plugin in
                channelRow(plugin)
            }

            if !cowork.channelPairings.isEmpty {
                pairingSection
            }
            if !cowork.channelUsers.isEmpty {
                usersSection
            }
        }
        .padding(14)
        .background(PrismTheme.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func channelRow(_ plugin: CoworkChannelPlugin) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plugin.name ?? plugin.id)
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                if plugin.isEnabled {
                    Text(plugin.isConnected ? L10n.channelConnected : L10n.channelDisconnected)
                        .font(.ps(8, weight: .semibold))
                        .foregroundStyle(plugin.isConnected ? PrismTheme.signalAllow : PrismTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (plugin.isConnected ? PrismTheme.signalAllow : PrismTheme.textTertiary).opacity(0.12)
                            )
                        )
                }
                if let bot = plugin.botUsername, !bot.isEmpty {
                    Text("@\(bot)")
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textSecondary)
                }
                Spacer()
                if plugin.isEnabled {
                    Button(L10n.channelDisable) {
                        Task { await cowork.disableChannel(pluginID: plugin.id) }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(10))
                }
            }

            if !plugin.isEnabled {
                HStack(spacing: 8) {
                    SecureField(L10n.botToken, text: Binding(
                        get: { tokenDrafts[plugin.id] ?? "" },
                        set: { tokenDrafts[plugin.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.ps(10, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PrismTheme.surfaceMuted.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button(L10n.channelEnable) {
                        let token = tokenDrafts[plugin.id] ?? ""
                        guard !token.isEmpty else {
                            cowork.statusMessage = L10n.channelTokenRequired
                            return
                        }
                        Task {
                            if await cowork.testChannelToken(pluginID: plugin.id, token: token) != nil {
                                await cowork.enableChannel(pluginID: plugin.id, token: token)
                                tokenDrafts[plugin.id] = nil
                            }
                        }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(10, weight: .semibold))
                    .disabled((tokenDrafts[plugin.id] ?? "").isEmpty)
                }
            }
        }
        .padding(10)
        .background(PrismTheme.surfaceMuted.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.pendingPairings)
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.accentSecondary)
            ForEach(cowork.channelPairings) { pairing in
                HStack {
                    Text(pairing.displayName ?? pairing.platformUserID ?? pairing.code)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text(pairing.platformType ?? "")
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                    Spacer()
                    Button(L10n.approve) {
                        Task { await cowork.approvePairing(code: pairing.code) }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(9, weight: .semibold))
                    .foregroundStyle(PrismTheme.signalAllow)
                    Button(L10n.reject) {
                        Task { await cowork.rejectPairing(code: pairing.code) }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(9))
                    .foregroundStyle(PrismTheme.signalDeny)
                }
            }
        }
    }

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.authorizedUsers)
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)
            ForEach(cowork.channelUsers) { user in
                HStack {
                    Text(user.displayName ?? user.platformUserID ?? user.id)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text(user.platformType ?? "")
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                    Spacer()
                    Button(L10n.revoke) {
                        Task { await cowork.revokeChannelUser(id: user.id) }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(9))
                    .foregroundStyle(PrismTheme.signalDeny)
                }
            }
        }
    }
}
