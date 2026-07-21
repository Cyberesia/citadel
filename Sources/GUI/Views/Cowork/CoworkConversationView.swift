import SwiftUI

struct CoworkConversationView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var composerText = ""
    @State private var isRenamingTitle = false
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if let notice = cowork.toolsDisabledNotice {
                CoworkInfoBanner(message: notice)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if let tip = tipsMessage {
                CoworkTipsBanner(message: tip)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Divider().opacity(0.2)
            HStack {
                TextField(L10n.searchMessages, text: $cowork.messageSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.ps(10))
                    .onSubmit { Task { await cowork.searchActiveMessages() } }
                if !cowork.messageSearchResults.isEmpty {
                    Text("\(cowork.messageSearchResults.count)")
                        .font(.ps(9, weight: .bold))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            Divider().opacity(0.2)
            HStack(spacing: 0) {
                CoworkWorkspacePanel()
                Divider().opacity(0.15)
                chatColumn
                Divider().opacity(0.15)
                CoworkPreviewPanel()
            }
            CoworkConfirmationSheet()
            composer
        }
        .onAppear {
            if let id = cowork.activeConversationID {
                Task {
                    await cowork.loadConversationDetail(id)
                    await cowork.loadMessages(for: id)
                    await cowork.refreshWorkspace()
                    await cowork.refreshConfirmations()
                    await cowork.refreshSlashCommands()
                }
            }
            cowork.requestComposerFocus()
        }
    }

    private var tipsMessage: String? {
        if let status = cowork.statusMessage, !status.isEmpty {
            return cowork.localizedStatus(status)
        }
        if let tip = cowork.messages.last(where: { $0.isTips })?.errorMessage ?? cowork.messages.last(where: { $0.isTips })?.textBody,
           !tip.isEmpty {
            if !cowork.activeModelSupportsTools && CoworkState.isStaleToolRejection(tip) {
                return nil
            }
            return L10n.statusLine(tip, chatOnly: !cowork.activeModelSupportsTools)
        }
        return nil
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                cowork.closeConversation()
            } label: {
                Label(L10n.back, systemImage: "chevron.left")
                    .font(.ps(12, weight: .semibold))
            }
            .buttonStyle(PrismHandButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                titleView
                if cowork.isStreaming {
                    Text(L10n.agentWorking)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.accentSecondary)
                }
            }

            Spacer()

            CoworkConversationUsageView(stats: cowork.conversationUsage, lastTurn: cowork.lastTokenUsage)

            Menu {
                Button(L10n.resetSession) {
                    Task { await cowork.resetActiveConversation() }
                }
                Button(L10n.forkSession) {
                    Task { await cowork.forkActiveConversation() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.ps(13))
            }
            .menuStyle(.borderlessButton)

            CoworkSessionModelMenu()
            CoworkAssistantPicker()
            CoworkAgentModePicker()
            CoworkSkillsPicker()
            CoworkMcpPicker()
            confirmationBadge

            if cowork.isStreaming {
                Button(L10n.stop) { Task { await cowork.stopGeneration() } }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(11, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: cowork.selectedMcpIDs) { _ in
            Task { await cowork.applyMcpSelectionToActiveConversation() }
        }
    }

    /// Badge with the number of pending tool confirmations; click re-opens the queue.
    @ViewBuilder
    private var confirmationBadge: some View {
        if !cowork.pendingConfirmations.isEmpty {
            Button {
                cowork.activeConfirmation = cowork.pendingConfirmations.first
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                    Text("\(cowork.pendingConfirmations.count)")
                }
                .font(.ps(10, weight: .bold))
                .foregroundStyle(PrismTheme.signalDeny)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PrismTheme.signalDeny.opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(PrismHandButtonStyle())
            .help(L10n.pendingConfirmations(cowork.pendingConfirmations.count))
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isRenamingTitle {
            TextField(L10n.sessionName, text: $renameDraft, onCommit: commitRename)
                .textFieldStyle(.plain)
                .font(.ps(13, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
                .frame(maxWidth: 260)
                .onExitCommand { isRenamingTitle = false }
        } else {
            Text(cowork.activeConversation?.name ?? L10n.session)
                .font(.ps(13, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    renameDraft = cowork.activeConversation?.name ?? ""
                    isRenamingTitle = true
                }
                .help(L10n.renameSessionHelp)
        }
    }

    private func commitRename() {
        isRenamingTitle = false
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != cowork.activeConversation?.name,
              let id = cowork.activeConversationID else { return }
        Task { await cowork.renameConversation(id, name: trimmed) }
    }

    private var chatColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if cowork.hasMoreMessages {
                        HStack {
                            Spacer()
                            Button {
                                Task { await cowork.loadOlderMessages() }
                            } label: {
                                Label(L10n.loadEarlierMessages, systemImage: "arrow.up.circle")
                                    .font(.ps(10, weight: .semibold))
                            }
                            .buttonStyle(PrismHandButtonStyle())
                            Spacer()
                        }
                    }
                    ForEach(displayMessages, id: \.stableID) { message in
                        messageView(message)
                            .id(message.stableID)
                    }
                    ForEach(liveOnlyToolIDs, id: \.self) { msgID in
                        ForEach(cowork.liveToolCalls[msgID] ?? []) { tool in
                            CoworkToolCallBubble(tool: tool)
                        }
                        .id("livetool-\(msgID)")
                    }
                    ForEach(streamingOnlyIDs, id: \.self) { msgID in
                        streamBubble(msgID: msgID)
                            .id("stream-\(msgID)")
                    }
                }
                .padding(16)
            }
            .onChange(of: displayMessages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: cowork.streamTick) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Tool calls streamed live that have no persisted message yet.
    private var liveOnlyToolIDs: [String] {
        cowork.liveToolOrder.filter { msgID in
            !cowork.messages.contains { $0.msgID == msgID }
        }
    }

    private var streamingOnlyIDs: [String] {
        cowork.liveStreamSegments.keys.filter { msgID in
            guard let message = cowork.messages.first(where: { $0.msgID == msgID }) else { return true }
            return message.textBody.isEmpty
        }
        .sorted()
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let streamID = streamingOnlyIDs.last {
            withAnimation(PrismMotion.quick) {
                proxy.scrollTo("stream-\(streamID)", anchor: .bottom)
            }
        } else if let last = displayMessages.last {
            withAnimation(PrismMotion.quick) {
                proxy.scrollTo(last.stableID, anchor: .bottom)
            }
        }
    }

    private var displayMessages: [CoworkMessage] {
        cowork.messages.filter { message in
            if message.isTips || message.hidden == true { return false }
            if let msgID = message.msgID,
               cowork.isStreaming,
               message.textBody.isEmpty,
               cowork.liveStreamSegments[msgID] != nil,
               !message.isUser {
                return false
            }
            if message.isToolMessage || message.isThinking { return true }
            if let msgID = message.msgID, let segment = cowork.liveStreamSegments[msgID] {
                return !message.textBody.isEmpty
                    || !segment.answer.isEmpty
                    || !segment.thinking.isEmpty
                    || message.type == "text"
            }
            return !message.textBody.isEmpty || message.type == "text"
        }
    }

    @ViewBuilder
    private func messageView(_ message: CoworkMessage) -> some View {
        if message.isThinking {
            CoworkThinkingCard(
                text: message.textBody,
                isThinking: cowork.isStreaming,
                collapseAfter: nil,
                persistedExpanded: nil
            )
        } else if message.isToolMessage {
            // Live WebSocket updates supersede the persisted snapshot while the turn runs.
            let live = message.msgID.flatMap { cowork.liveToolCalls[$0] }
            ForEach(live ?? CoworkToolCallNormalizer.normalize(message)) { tool in
                CoworkToolCallBubble(tool: tool)
            }
        } else {
            messageBubble(message)
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: CoworkMessage) -> some View {
        let msgID = message.msgID ?? ""
        let segment = cowork.liveStreamSegments[msgID]
        let isLive = segment != nil && cowork.isStreaming

        if message.isUser {
            CoworkMessageBubble(message: message, text: message.textBody, isUser: true)
        } else if isLive || !message.textBody.isEmpty {
            HStack {
                CoworkAssistantMessageContent(
                    msgID: message.msgID,
                    rawText: message.textBody,
                    isStreaming: isLive,
                    segment: segment,
                    supportsImplicitLeadingThinking: cowork.supportsImplicitLeadingThinking,
                    onPersistThinkingExpanded: { expanded in
                        cowork.setThinkingCardExpanded(msgID: msgID, expanded: expanded)
                    }
                )
                Spacer(minLength: 24)
            }
        } else if cowork.isStreaming {
            HStack {
                CoworkWaitingWaveform()
                Spacer(minLength: 24)
            }
        }
    }

    private func streamBubble(msgID: String) -> some View {
        HStack {
            CoworkAssistantMessageContent(
                msgID: msgID,
                rawText: "",
                isStreaming: true,
                segment: cowork.liveStreamSegments[msgID],
                supportsImplicitLeadingThinking: cowork.supportsImplicitLeadingThinking,
                onPersistThinkingExpanded: { expanded in
                    cowork.setThinkingCardExpanded(msgID: msgID, expanded: expanded)
                }
            )
            Spacer(minLength: 24)
        }
    }

    private var composer: some View {
        CoworkSessionComposer(text: $composerText)
    }
}
