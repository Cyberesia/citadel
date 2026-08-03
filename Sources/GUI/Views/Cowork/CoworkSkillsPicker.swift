import SwiftUI

struct CoworkSkillsPicker: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var showPopover = false

    /// One row per visible title — avoids duplicate Infomaniak hiring aliases from upstream.
    private var pickerSkills: [CoworkSkill] {
        var seen = Set<String>()
        return cowork.availableSkills.filter { skill in
            let key = skill.displayTitle.lowercased()
            return seen.insert(key).inserted
        }
    }

    var body: some View {
        if cowork.availableSkills.isEmpty { EmptyView() }
        else {
            CoworkConfigChipTrigger(
                icon: "puzzlepiece.extension",
                title: skillsLabel,
                tint: skillsTint,
                isPresented: $showPopover
            ) {
                popoverContent
                    .prismPopoverChrome(width: 400, maxHeight: 440)
            }
            .help(cowork.activeModelSupportsTools ? L10n.skillsHelp : L10n.toolsDisabledSkillsHelp)
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cowork.activeModelSupportsTools {
                Text(L10n.toolsDisabledSkillsHelp)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
            } else {
                Text(L10n.sessionSkillsPickerHelp)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(pickerSkills) { skill in
                            PrismSelectableRow(
                                title: skill.displayTitle,
                                subtitle: skill.displayDetail,
                                isSelected: cowork.selectedSkillIDs.contains(skill.name)
                            ) {
                                toggleSkill(skill.name)
                            }
                        }
                    }
                }
            }
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

    private func toggleSkill(_ name: String) {
        guard cowork.activeModelSupportsTools else { return }
        if cowork.selectedSkillIDs.contains(name) {
            cowork.selectedSkillIDs.remove(name)
        } else {
            cowork.selectedSkillIDs.insert(name)
        }
        Task { await cowork.applySkillsToActiveConversation() }
    }
}

struct CoworkAgentModePicker: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var showPopover = false

    private var mode: CoworkUserFacing.PermissionMode {
        CoworkUserFacing.PermissionMode.from(stored: cowork.agentPermissionMode)
    }

    var body: some View {
        CoworkConfigChipTrigger(
            icon: "shield.lefthalf.filled",
            title: L10n.permissionsChip(mode.title),
            tint: PrismTheme.textSecondary,
            isPresented: $showPopover
        ) {
            popoverContent
                .prismPopoverChrome(width: 340, maxHeight: 320)
        }
        .help(mode.detail)
    }

    private var popoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(CoworkUserFacing.PermissionMode.allCases) { item in
                    PrismSelectableRow(
                        title: item.title,
                        subtitle: item.detail,
                        isSelected: mode == item
                    ) {
                        cowork.agentPermissionMode = item.rawValue
                        Task { await cowork.applyPermissionModeToActiveConversation() }
                        showPopover = false
                    }
                }
            }
        }
    }
}
