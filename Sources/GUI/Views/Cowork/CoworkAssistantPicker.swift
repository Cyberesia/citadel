import SwiftUI

struct CoworkAssistantPicker: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        Menu {
            ForEach(cowork.assistants.filter { $0.enabled != false }, id: \.id) { assistant in
                Button {
                    Task { await cowork.switchActiveConversationAssistant(assistant.id) }
                } label: {
                    if cowork.selectedAssistantID == assistant.id {
                        Label(assistant.displayName, systemImage: "checkmark")
                    } else {
                        Text(assistant.displayName)
                    }
                }
            }
        } label: {
            CoworkConfigChip(
                icon: "sparkles",
                title: cowork.selectedAssistant?.displayName ?? "Assistant",
                tint: PrismTheme.textPrimary
            )
        }
        .menuStyle(.borderlessButton)
    }
}

struct CoworkMcpPicker: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        Menu {
            if !cowork.activeModelSupportsTools {
                Text(L10n.toolsDisabledMcpHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if cowork.mcpServers.isEmpty {
                Text(L10n.noMcpServers)
            } else {
                ForEach(cowork.mcpServers, id: \.id) { server in
                    Toggle(server.name, isOn: Binding(
                        get: { cowork.selectedMcpIDs.contains(server.id) },
                        set: { enabled in
                            if enabled { cowork.selectedMcpIDs.insert(server.id) }
                            else { cowork.selectedMcpIDs.remove(server.id) }
                            Task { await cowork.applyMcpSelectionToActiveConversation() }
                        }
                    ))
                }
            }
            Divider()
            Button(L10n.manageMcp) { cowork.showMcpSheet = true }
        } label: {
            CoworkConfigChip(
                icon: "wrench.and.screwdriver.fill",
                title: mcpLabel,
                tint: cowork.activeModelSupportsTools ? PrismTheme.textSecondary : PrismTheme.textTertiary
            )
        }
        .menuStyle(.borderlessButton)
        .help(cowork.activeModelSupportsTools ? L10n.mcpToolsLabel : L10n.toolsDisabledMcpHelp)
        .disabled(!cowork.activeModelSupportsTools && cowork.mcpServers.isEmpty)
    }

    private var mcpLabel: String {
        guard cowork.activeModelSupportsTools else { return L10n.mcpOff }
        return L10n.mcpCount(cowork.selectedMcpIDs.count)
    }
}
