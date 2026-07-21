import SwiftUI

struct CoworkMcpSettingsView: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss
    /// When presented as a sheet (e.g. from the assistant picker). False for the Tools tab.
    var isModal: Bool = false
    @State private var importJSON = ""
    @State private var importError: String?
    @State private var isImporting = false

    private var detectedServers: [CoworkMcpDetectedServer] {
        cowork.mcpAgentConfigs.flatMap(\.servers)
    }

    private var importableDetected: [CoworkMcpDetectedServer] {
        detectedServers.filter(\.canImport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.mcpTools)
                    .font(.ps(16, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Spacer()
                Button(L10n.refresh) {
                    Task {
                        await cowork.refreshMcpServers()
                        await cowork.refreshMcpAgentConfigs()
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(11))
                if isModal {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.ps(11, weight: .semibold))
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .help(L10n.close)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Text(L10n.mcpSubtitle)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
                .padding(.horizontal, 16)

            Text(L10n.mcpUsageHelp)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
                .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    CoworkSkillsHubView()
                    installedSection
                    detectedSection
                    manualImportSection
                }
                .padding(16)
            }

            if isModal {
                HStack {
                    Spacer()
                    Button(L10n.close) { dismiss() }
                        .buttonStyle(PrismHandButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            cowork.startCoreIfNeeded()
            Task {
                await cowork.refreshMcpServers()
                await cowork.refreshMcpAgentConfigs()
                await cowork.refreshSkills()
                await cowork.refreshMcpOAuth()
            }
        }
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L10n.installedServers, count: cowork.mcpServers.count)
            if cowork.mcpServers.isEmpty {
                emptyHint(L10n.mcpEmpty)
            } else {
                ForEach(cowork.mcpServers, id: \.id) { server in
                    mcpRow(server)
                }
            }
        }
    }

    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L10n.detectedAgents, count: detectedServers.count)
            if detectedServers.isEmpty {
                emptyHint(L10n.mcpDetectedEmpty)
            } else {
                ForEach(cowork.mcpAgentConfigs, id: \.source) { group in
                    if !group.servers.isEmpty {
                        Text(group.source.uppercased())
                            .font(.ps(9, weight: .bold))
                            .foregroundStyle(PrismTheme.textTertiary)
                            .padding(.top, 4)
                        ForEach(group.servers) { server in
                            detectedRow(server)
                        }
                    }
                }
            }
        }
    }

    private var manualImportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L10n.importMcpJSON, count: nil)
            Text(L10n.importMcpHelp)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
            TextEditor(text: $importJSON)
                .font(.ps(11, design: .monospaced))
                .frame(height: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(PrismTheme.surfaceMuted.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let importError {
                Text(importError)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.signalDeny)
            }
            Button(isImporting ? L10n.importing : L10n.importJSON) {
                Task { await runImport() }
            }
            .disabled(isImporting || importJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.ps(12, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
            if let count {
                Text("\(count)")
                    .font(.ps(9, weight: .bold))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PrismTheme.surfaceMuted.opacity(0.6))
                    .clipShape(Capsule())
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.ps(10))
            .foregroundStyle(PrismTheme.textTertiary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PrismTheme.surfaceMuted.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func mcpRow(_ server: CoworkMcpServer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(server.displayName)
                        .font(.ps(12, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    if server.builtin == true {
                        Text(L10n.builtin)
                            .font(.ps(9, weight: .bold))
                            .foregroundStyle(PrismTheme.accentSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PrismTheme.accentSoft)
                            .clipShape(Capsule())
                    }
                }
                if let description = server.displayDescription {
                    Text(description)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textSecondary)
                        .lineLimit(2)
                }
                if let tools = server.tools, !tools.isEmpty {
                    Text(L10n.toolsCount(tools.count))
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                if let url = server.httpURL {
                    oauthControls(serverURL: url)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { server.enabled },
                set: { _ in Task { await cowork.toggleMcpServer(server.id) } }
            ))
            .toggleStyle(PrismHandToggleStyle(kind: .switch))
            .labelsHidden()
            if server.builtin != true {
                Button {
                    Task { await cowork.deleteMcpServer(server.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                .buttonStyle(PrismHandButtonStyle())
            }
        }
        .padding(12)
        .background(PrismTheme.surfaceMuted.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// OAuth sign-in / sign-out controls for HTTP MCP servers.
    private func oauthControls(serverURL: String) -> some View {
        HStack(spacing: 8) {
            if cowork.mcpOAuthServers.contains(serverURL) {
                Label(L10n.oauthConnected, systemImage: "checkmark.seal.fill")
                    .font(.ps(9, weight: .semibold))
                    .foregroundStyle(PrismTheme.signalAllow)
                Button(L10n.oauthLogout) {
                    Task { await cowork.mcpOAuthLogout(serverURL: serverURL) }
                }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(9))
            } else {
                Button(L10n.oauthLogin) {
                    Task { await cowork.mcpOAuthLogin(serverURL: serverURL) }
                }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(9, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PrismTheme.accentSoft)
                .clipShape(Capsule())
            }
        }
        .padding(.top, 2)
    }

    private func detectedRow(_ server: CoworkMcpDetectedServer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.displayName)
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                if let description = server.displayDescription {
                    Text(description)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textSecondary)
                        .lineLimit(2)
                }
                if let reason = server.importSkipReason, !server.canImport {
                    Text(reason)
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
            }
            Spacer()
            if server.canImport {
                Button(L10n.importAction) {
                    Task { await cowork.importDetectedMcpServer(server) }
                }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PrismTheme.accentSoft)
                .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(PrismTheme.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func runImport() async {
        isImporting = true
        importError = nil
        defer { isImporting = false }
        do {
            try await cowork.importMcpFromJSON(importJSON)
            importJSON = ""
            await cowork.refreshMcpAgentConfigs()
        } catch {
            importError = error.localizedDescription
        }
    }
}
