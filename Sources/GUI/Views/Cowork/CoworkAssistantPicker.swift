import SwiftUI

struct CoworkAssistantPicker: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var showPopover = false

    var body: some View {
        CoworkConfigChipTrigger(
            icon: "sparkles",
            title: cowork.selectedAssistant?.displayName ?? "Assistant",
            tint: PrismTheme.textPrimary,
            isPresented: $showPopover
        ) {
            popoverContent
                .prismPopoverChrome(width: 300, maxHeight: 360)
        }
    }

    private var popoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(cowork.assistants.filter { $0.enabled != false }, id: \.id) { assistant in
                    PrismSelectableRow(
                        title: assistant.displayName,
                        isSelected: cowork.selectedAssistantID == assistant.id
                    ) {
                        Task { await cowork.switchActiveConversationAssistant(assistant.id) }
                        showPopover = false
                    }
                }
            }
        }
    }
}

struct CoworkMcpPicker: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var showPopover = false

    private var enabledServers: [CoworkMcpServer] {
        cowork.enabledMcpServers
    }

    var body: some View {
        CoworkConfigChipTrigger(
            icon: "wrench.and.screwdriver.fill",
            title: mcpLabel,
            tint: cowork.activeModelSupportsTools ? PrismTheme.textSecondary : PrismTheme.textTertiary,
            isPresented: $showPopover
        ) {
            popoverContent
                .prismPopoverChrome(width: 360, maxHeight: 380)
        }
        .help(cowork.activeModelSupportsTools ? L10n.mcpToolsLabel : L10n.toolsDisabledMcpHelp)
        .disabled(!cowork.activeModelSupportsTools && enabledServers.isEmpty)
    }

    @ViewBuilder
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cowork.activeModelSupportsTools {
                Text(L10n.toolsDisabledMcpHelp)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
            } else if enabledServers.isEmpty {
                Text(L10n.noMcpServers)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
            } else {
                Text(L10n.mcpPickerMultiSelectHelp)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(enabledServers, id: \.id) { server in
                            PrismSelectableRow(
                                title: server.pickerLabel,
                                subtitle: server.displayDescription,
                                isSelected: cowork.selectedMcpIDs.contains(server.id)
                            ) {
                                toggleServer(server.id)
                            }
                        }
                    }
                }
            }

            Divider().opacity(0.25)

            Button(L10n.manageMcp) {
                showPopover = false
                DispatchQueue.main.async { cowork.showMcpSheet = true }
            }
            .buttonStyle(PrismHandButtonStyle())
            .font(.ps(11, weight: .semibold))
        }
    }

    private var mcpLabel: String {
        guard cowork.activeModelSupportsTools else { return L10n.mcpOff }
        return L10n.mcpCount(cowork.selectedEnabledMcpCount)
    }

    private func toggleServer(_ id: String) {
        if cowork.selectedMcpIDs.contains(id) {
            cowork.selectedMcpIDs.remove(id)
        } else {
            cowork.selectedMcpIDs.insert(id)
        }
        Task { await cowork.applyMcpSelectionToActiveConversation() }
    }
}

/// Chip button that opens a custom Prism popover (replaces broken macOS Menu multi-line labels).
struct CoworkConfigChipTrigger<Popover: View>: View {
    let icon: String
    let title: String
    let tint: Color
    @Binding var isPresented: Bool
    @ViewBuilder var popover: () -> Popover

    var body: some View {
        Button { isPresented.toggle() } label: {
            CoworkConfigChip(icon: icon, title: title, tint: tint)
        }
        .buttonStyle(PrismHandButtonStyle())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popover()
        }
    }
}

/// Small capsule used for session configuration menus.
struct CoworkConfigChip: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.ps(8, weight: .bold))
        }
        .font(.ps(10, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PrismTheme.surfaceMuted.opacity(0.5))
        .clipShape(Capsule())
    }
}
