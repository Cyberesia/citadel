import SwiftUI

struct CoworkSkillsPicker: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        if cowork.availableSkills.isEmpty { EmptyView() }
        else {
            Menu {
                if !cowork.activeModelSupportsTools {
                    Text(L10n.toolsDisabledSkillsHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.skillsExtend)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    ForEach(cowork.availableSkills) { skill in
                        Toggle(isOn: binding(for: skill.name)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.displayTitle)
                                if let detail = skill.displayDetail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } label: {
                CoworkConfigChip(
                    icon: "puzzlepiece.extension",
                    title: skillsLabel,
                    tint: skillsTint
                )
            }
            .menuStyle(.borderlessButton)
            .help(cowork.activeModelSupportsTools ? L10n.skillsHelp : L10n.toolsDisabledSkillsHelp)
        }
    }

    private var skillsTint: Color {
        if !cowork.activeModelSupportsTools { return PrismTheme.textTertiary }
        return cowork.selectedSkillIDs.isEmpty ? PrismTheme.textSecondary : PrismTheme.accent
    }

    private var skillsLabel: String {
        guard cowork.activeModelSupportsTools else { return L10n.skillsOff }
        return L10n.skillsCount(cowork.selectedSkillIDs.count)
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { cowork.selectedSkillIDs.contains(name) },
            set: { enabled in
                guard cowork.activeModelSupportsTools else { return }
                if enabled { cowork.selectedSkillIDs.insert(name) }
                else { cowork.selectedSkillIDs.remove(name) }
                Task { await cowork.applySkillsToActiveConversation() }
            }
        )
    }
}

struct CoworkAgentModePicker: View {
    @EnvironmentObject var cowork: CoworkState

    private var mode: CoworkUserFacing.PermissionMode {
        CoworkUserFacing.PermissionMode.from(stored: cowork.agentPermissionMode)
    }

    var body: some View {
        Menu {
            ForEach(CoworkUserFacing.PermissionMode.allCases) { item in
                Button {
                    cowork.agentPermissionMode = item.rawValue
                    Task { await cowork.applyPermissionModeToActiveConversation() }
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.title)
                        Text(item.detail)
                            .font(.caption)
                    }
                }
            }
        } label: {
            CoworkConfigChip(
                icon: "shield.lefthalf.filled",
                title: L10n.permissionsChip(mode.title),
                tint: PrismTheme.textSecondary
            )
        }
        .menuStyle(.borderlessButton)
        .help(mode.detail)
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
