import SwiftUI

struct CoworkSessionsView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var renameTarget: CoworkConversation?
    @State private var renameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.coworkSessions)
                    .font(.ps(16, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Spacer()
                Button(L10n.refresh) { Task { await cowork.refreshConversations() } }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(11))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if cowork.conversations.isEmpty {
                coworkPlaceholder(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: L10n.noSessionsTitle,
                    subtitle: L10n.noSessionsSubtitle
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cowork.conversations, id: \.id) { conversation in
                            sessionRow(conversation)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            cowork.startCoreIfNeeded()
            Task { await cowork.refreshConversations() }
        }
        .sheet(item: $renameTarget) { conversation in
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.renameSession)
                    .font(.ps(14, weight: .semibold))
                TextField(L10n.sessionName, text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                HStack {
                    Spacer()
                    Button(L10n.cronCancel) { renameTarget = nil }
                    Button(L10n.rename) {
                        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        renameTarget = nil
                        guard !trimmed.isEmpty else { return }
                        Task { await cowork.renameConversation(conversation.id, name: trimmed) }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }

    private func sessionRow(_ conversation: CoworkConversation) -> some View {
        Button {
            Task { await cowork.openConversation(conversation.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(PrismTheme.accentSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.name ?? L10n.untitled)
                        .font(.ps(12, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                        .lineLimit(1)
                    if let display = conversation.modelDisplay(providers: cowork.providers) {
                        Text(display.summary)
                            .font(.ps(10))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .lineLimit(2)
                    }
                    if let when = conversation.displayUpdatedLabel {
                        Text(when)
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.textTertiary)
                    }
                }
                Spacer()
                Button {
                    Task { await cowork.deleteConversation(conversation.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                .buttonStyle(PrismHandButtonStyle())
            }
            .padding(12)
            .background(PrismTheme.surfaceMuted.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PrismHandButtonStyle())
        .contextMenu {
            Button(L10n.renameEllipsis) {
                renameTarget = conversation
                renameDraft = conversation.name ?? ""
            }
            Button(L10n.delete, role: .destructive) {
                Task { await cowork.deleteConversation(conversation.id) }
            }
        }
    }
}
