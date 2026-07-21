import SwiftUI

/// Teams list + creation (plan Phase 5). Opening a team shows the multi-slot workspace.
struct CoworkTeamsView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var showCreate = false

    var body: some View {
        Group {
            if cowork.activeTeamID != nil {
                CoworkTeamWorkspaceView()
            } else {
                teamList
            }
        }
        .onAppear { Task { await cowork.refreshTeams() } }
        .sheet(isPresented: $showCreate) {
            CoworkTeamCreateSheet()
                .environmentObject(cowork)
        }
    }

    private var teamList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.coworkTeams)
                    .font(.ps(18, weight: .bold))
                Spacer()
                Button(L10n.newTeam) { showCreate = true }
                    .buttonStyle(PrismHandButtonStyle())
            }

            if cowork.teams.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(PrismTheme.textTertiary)
                    Text(L10n.teamsEmpty)
                        .font(.ps(12))
                        .foregroundStyle(PrismTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Button(L10n.newTeam) { showCreate = true }
                        .buttonStyle(PrismHandButtonStyle())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(PrismTheme.accentSoft)
                        .clipShape(Capsule())
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(cowork.teams) { team in
                            teamRow(team)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func teamRow(_ team: CoworkTeam) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.ps(16))
                .foregroundStyle(PrismTheme.accentSecondary)
                .frame(width: 34, height: 34)
                .background(PrismTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.ps(13, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(L10n.teamMemberCount(team.assistants.count))
                    if let workspace = team.workspace, !workspace.isEmpty {
                        Text("·")
                        Text((workspace as NSString).lastPathComponent)
                    }
                }
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textSecondary)
            }

            Spacer()

            Button(L10n.openTeam) {
                Task { await cowork.openTeam(team.id) }
            }
            .buttonStyle(PrismHandButtonStyle())
            .font(.ps(11, weight: .semibold))

            Menu {
                Button(L10n.renameTeam) { rename(team) }
                Button(L10n.deleteTeam, role: .destructive) {
                    Task { await cowork.deleteTeam(team.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.ps(13))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
        }
        .padding(12)
        .background(PrismTheme.surfaceMuted.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func rename(_ team: CoworkTeam) {
        let alert = NSAlert()
        alert.messageText = L10n.renameTeam
        let field = NSTextField(string: team.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.rename)
        alert.addButton(withTitle: L10n.cronCancel)
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            Task { await cowork.renameTeam(team.id, name: name) }
        }
    }
}

// MARK: - Create sheet

struct CoworkTeamCreateSheet: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var leaderID: String?
    @State private var memberIDs: [String] = []
    @State private var workspace = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.newTeam).font(.headline)

            TextField(L10n.teamName, text: $name)

            Picker(L10n.teamLeader, selection: $leaderID) {
                ForEach(cowork.assistants) { assistant in
                    Text(assistant.displayName).tag(Optional(assistant.id))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.teamMembers)
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.textSecondary)
                ForEach(Array(memberIDs.enumerated()), id: \.offset) { index, memberID in
                    HStack {
                        Picker("", selection: Binding(
                            get: { memberIDs[index] },
                            set: { memberIDs[index] = $0 }
                        )) {
                            ForEach(cowork.assistants) { assistant in
                                Text(assistant.displayName).tag(assistant.id)
                            }
                        }
                        .labelsHidden()
                        Button {
                            memberIDs.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(PrismHandButtonStyle())
                    }
                    .id("\(index)-\(memberID)")
                }
                Button {
                    if let first = cowork.assistants.first?.id {
                        memberIDs.append(first)
                    }
                } label: {
                    Label(L10n.addMember, systemImage: "plus.circle")
                        .font(.ps(11))
                }
                .buttonStyle(PrismHandButtonStyle())
            }

            HStack {
                TextField(L10n.workspaceFolder, text: $workspace)
                Button(L10n.browse) { pickFolder() }
                    .buttonStyle(PrismHandButtonStyle())
            }

            HStack {
                Spacer()
                Button(L10n.cronCancel) { dismiss() }
                    .buttonStyle(PrismHandButtonStyle())
                Button(L10n.createTeam) {
                    Task {
                        await cowork.createTeam(
                            name: name.isEmpty ? L10n.newTeam : name,
                            leaderAssistantID: leaderID,
                            memberAssistantIDs: memberIDs,
                            workspace: workspace.isEmpty ? nil : workspace
                        )
                        dismiss()
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(leaderID == nil || cowork.isTeamBusy)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if leaderID == nil { leaderID = cowork.assistants.first?.id }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            workspace = url.path
        }
    }
}
