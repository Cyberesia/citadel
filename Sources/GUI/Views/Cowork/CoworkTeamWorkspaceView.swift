import SwiftUI

/// Multi-column team workspace (plan Phase 5): leader + member slots side by side,
/// a shared task composer routed to the leader, and per-slot controls.
struct CoworkTeamWorkspaceView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var taskDraft = ""
    @State private var showAddMember = false
    @State private var newMemberID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            slotColumns
            Divider().opacity(0.15)
            composer
        }
        .sheet(isPresented: $showAddMember) { addMemberSheet }
        .onAppear {
            Task { await cowork.refreshTeamAssistantEligibility() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                cowork.closeTeam()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.ps(12, weight: .semibold))
            }
            .buttonStyle(PrismHandButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                Text(cowork.activeTeam?.name ?? L10n.coworkTeams)
                    .font(.ps(14, weight: .bold))
                    .foregroundStyle(PrismTheme.textPrimary)
                if let workspace = cowork.activeTeam?.workspace, !workspace.isEmpty {
                    Text(workspace)
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            runStateBadge

            Button {
                let eligible = cowork.assistantsEligibleForTeam(excluding: cowork.activeTeamAssistantIDs())
                newMemberID = eligible.first?.id
                showAddMember = true
            } label: {
                Label(L10n.addMember, systemImage: "person.badge.plus")
                    .font(.ps(11))
            }
            .buttonStyle(PrismHandButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var runStateBadge: some View {
        let running = cowork.teamRunState?.isRunning == true
        HStack(spacing: 6) {
            Circle()
                .fill(running ? PrismTheme.signalAllow : PrismTheme.textTertiary)
                .frame(width: 7, height: 7)
            Text(running ? L10n.teamRunning : L10n.teamIdle)
                .font(.ps(10, weight: .medium))
                .foregroundStyle(PrismTheme.textSecondary)
            if running {
                Button(L10n.cancelRun) {
                    Task { await cowork.cancelActiveTeamRun() }
                }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.signalDeny)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PrismTheme.surfaceMuted.opacity(0.4))
        .clipShape(Capsule())
    }

    // MARK: - Slots

    private var slotColumns: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 12) {
                if let team = cowork.activeTeam {
                    ForEach(orderedSlots(team)) { slot in
                        slotColumn(slot)
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func orderedSlots(_ team: CoworkTeam) -> [CoworkTeamAssistant] {
        let leaders = team.assistants.filter(\.isLeader)
        return leaders + team.assistants.filter { !$0.isLeader }
    }

    private func slotColumn(_ slot: CoworkTeamAssistant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            slotHeader(slot)
            Divider().opacity(0.12)
            slotFeed(slot)
            slotComposer(slot)
        }
        .padding(10)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            slot.isLeader
                ? PrismTheme.accentSoft.opacity(0.5)
                : PrismTheme.surfaceMuted.opacity(0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func slotHeader(_ slot: CoworkTeamAssistant) -> some View {
        HStack(spacing: 8) {
            Image(systemName: slot.isLeader ? "crown.fill" : "person.fill")
                .font(.ps(11))
                .foregroundStyle(slot.isLeader ? PrismTheme.accent : PrismTheme.textSecondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(slot.assistantName)
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                    .lineLimit(1)
                Text(slot.isLeader ? L10n.teamLeader : (slot.status ?? L10n.teamMember))
                    .font(.ps(9))
                    .foregroundStyle(PrismTheme.textTertiary)
            }

            Spacer()

            if let pending = slot.pendingConfirmations, pending > 0 {
                Text("\(pending)")
                    .font(.ps(9, weight: .bold))
                    .foregroundStyle(PrismTheme.signalDeny)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PrismTheme.signalDeny.opacity(0.14))
                    .clipShape(Capsule())
            }

            Menu {
                if cowork.teamRunState?.isRunning == true {
                    Button(L10n.pauseAgent) {
                        Task { await cowork.pauseTeamSlot(slot.slotID) }
                    }
                    Button(L10n.cancelAgent) {
                        Task { await cowork.cancelTeamSlot(slot.slotID) }
                    }
                }
                if !slot.isLeader {
                    Button(L10n.removeMember, role: .destructive) {
                        Task { await cowork.removeTeamMember(slotID: slot.slotID) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.ps(11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
    }

    private func slotFeed(_ slot: CoworkTeamAssistant) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    let messages = visibleMessages(slot)
                    if messages.isEmpty {
                        if slot.conversationID == nil {
                            Text(L10n.teamSlotStarting)
                                .font(.ps(10))
                                .foregroundStyle(PrismTheme.textTertiary)
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(L10n.teamNoMessages)
                                .font(.ps(10))
                                .foregroundStyle(PrismTheme.textTertiary)
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(messages, id: \.stableID) { message in
                            slotMessage(message)
                                .id(message.stableID)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: visibleMessages(slot).last?.stableID) { last in
                if let last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func visibleMessages(_ slot: CoworkTeamAssistant) -> [CoworkMessage] {
        (cowork.teamSlotMessages[slot.slotID] ?? [])
            .filter { $0.hidden != true && (!$0.textBody.isEmpty || $0.isToolMessage) }
    }

    @ViewBuilder
    private func slotMessage(_ message: CoworkMessage) -> some View {
        if message.isToolMessage {
            HStack(spacing: 5) {
                Image(systemName: "wrench.fill")
                    .font(.ps(8))
                Text(message.content?.toolName ?? "tool")
                    .font(.ps(9, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(PrismTheme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PrismTheme.surfaceMuted.opacity(0.5))
            .clipShape(Capsule())
        } else {
            Text(message.textBody)
                .font(.ps(10))
                .foregroundStyle(message.isUser ? PrismTheme.textPrimary : PrismTheme.textSecondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(message.isUser ? PrismTheme.accentSoft : PrismTheme.surfaceMuted.opacity(0.45))
                )
                .textSelection(.enabled)
        }
    }

    private func slotComposer(_ slot: CoworkTeamAssistant) -> some View {
        SlotComposerField(placeholder: L10n.directMessage) { text in
            Task { await cowork.sendTeamSlotMessage(slotID: slot.slotID, content: text) }
        }
    }

    // MARK: - Leader composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(L10n.teamTaskPlaceholder, text: $taskDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.ps(12))
                .lineLimit(1...4)
                .onSubmit { sendTask() }

            Button {
                sendTask()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.ps(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(Circle().fill(PrismTheme.accentGradient))
            }
            .buttonStyle(PrismHandButtonStyle())
            .disabled(taskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cowork.isTeamBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PrismTheme.surfaceMuted.opacity(0.25))
    }

    private func sendTask() {
        let text = taskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        taskDraft = ""
        Task { await cowork.sendTeamTask(text) }
    }

    // MARK: - Add member sheet

    private var addMemberSheet: some View {
        let eligible = cowork.assistantsEligibleForTeam(excluding: cowork.activeTeamAssistantIDs())
        return VStack(alignment: .leading, spacing: 14) {
            Text(L10n.addMember).font(.headline)
            Text(L10n.teamCLIAuthHint)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrismDropdownField(
                label: L10n.teamMember,
                selection: $newMemberID,
                options: eligible.map { assistant in
                    PrismDropdownOption(
                        value: assistant.id,
                        title: assistant.displayName,
                        subtitle: assistant.isAionrs ? nil : assistant.displayBackendType
                    )
                },
                leadingIcon: "person.badge.plus"
            )
            if eligible.isEmpty {
                Text(L10n.teamMemberUnavailable)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            if cowork.isTeamBusy {
                PrismActivityBanner(
                    icon: "person.badge.plus",
                    message: cowork.teamActivityMessage ?? L10n.teamAddingMember,
                    compact: true
                )
            }
            if let status = cowork.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.signalDeny)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L10n.cronCancel) { showAddMember = false }
                    .buttonStyle(PrismHandButtonStyle())
                Button(L10n.addMember) {
                    if let id = newMemberID {
                        Task {
                            let ok = await cowork.addTeamMember(assistantID: id)
                            if ok { showAddMember = false }
                        }
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(newMemberID == nil || eligible.isEmpty || cowork.isTeamBusy)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            Task { await cowork.refreshTeamAssistantEligibility() }
            if newMemberID == nil || !eligible.contains(where: { $0.id == newMemberID }) {
                newMemberID = eligible.first?.id
            }
        }
    }
}

/// Small self-clearing composer used inside each slot column.
private struct SlotComposerField: View {
    let placeholder: String
    let onSend: (String) -> Void
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.ps(10))
                .onSubmit { send() }
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.ps(13))
                    .foregroundStyle(PrismTheme.accent)
            }
            .buttonStyle(PrismHandButtonStyle())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(PrismTheme.surfaceMuted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        onSend(text)
    }
}
