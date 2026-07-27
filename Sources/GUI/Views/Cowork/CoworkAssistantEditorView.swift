import SwiftUI

struct CoworkAssistantEditorView: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss

    let assistantID: String
    @State private var source: String?
    @State private var name = ""
    @State private var description = ""
    @State private var rules = ""
    @State private var recommendedPromptsText = ""
    @State private var enabled = true
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var initialEnabled = true

    private var isBuiltin: Bool { source == "builtin" }
    private var isGenerated: Bool { source == "generated" }
    private var profileFieldsEditable: Bool { !isBuiltin && !isGenerated }
    private var descriptionEditable: Bool { !isBuiltin }
    private var rulesEditable: Bool { !isBuiltin }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                Text(L10n.assistantLoadFailed)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        profileSection
                        rulesSection
                        promptsSection
                        Toggle(L10n.enabled, isOn: $enabled)
                            .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
                            .onChange(of: enabled) { _, newValue in
                                guard isBuiltin, !isLoading else { return }
                                Task { await saveEnabledOnly(newValue) }
                            }
                        if isBuiltin {
                            Text(L10n.assistantBuiltinEnabledHelp)
                                .font(.ps(10))
                                .foregroundStyle(PrismTheme.textTertiary)
                        }
                    }
                }
            }
            footer
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.assistantEditor).font(.ps(16, weight: .bold))
            if isBuiltin {
                Text(L10n.assistantBuiltinBadge)
                    .font(.ps(9, weight: .bold))
                    .foregroundStyle(PrismTheme.accentSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(PrismTheme.accentSoft))
            }
            Spacer()
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.assistantName, text: $name)
                .disabled(!profileFieldsEditable)
            TextField(L10n.assistantDescription, text: $description)
                .disabled(!descriptionEditable)
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isBuiltin ? L10n.assistantAbout : L10n.systemPrompt).font(.ps(11, weight: .semibold))
            if isBuiltin {
                Text(L10n.assistantRulesReadOnlyHelp)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                Text(CoworkUserFacing.assistantBuiltinOverview(id: assistantID))
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(PrismTheme.surfaceMuted.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                if isGenerated {
                    Text(L10n.assistantRulesReadOnlyHelp)
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                TextEditor(text: $rules)
                    .font(.ps(12, design: .monospaced))
                    .frame(minHeight: 160)
                    .disabled(!rulesEditable)
                    .opacity(rulesEditable ? 1 : 0.85)
            }
        }
    }

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.recommendedPrompts).font(.ps(11, weight: .semibold))
            Text(L10n.recommendedPromptsHelp)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
            TextEditor(text: $recommendedPromptsText)
                .font(.ps(11, design: .monospaced))
                .frame(minHeight: 72)
                .disabled(isBuiltin)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if isBuiltin {
                Button(L10n.close) { dismiss() }
                    .buttonStyle(PrismHandButtonStyle())
            } else {
                Button(L10n.cronCancel) { dismiss() }
                    .buttonStyle(PrismHandButtonStyle())
                    .disabled(isSaving)
                Button(L10n.cronSave) {
                    Task { await save() }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(isLoading || loadFailed || isSaving || (profileFieldsEditable && name.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        let locale = CitadelLocale.current.rawValue
        guard let detail = await cowork.loadAssistantDetail(assistantID) else {
            loadFailed = true
            return
        }

        source = detail.source
        let localizedName = detail.profile.localizedName(locale: locale)
        let localizedDescription = detail.profile.localizedDescription(locale: locale)
        name = CoworkUserFacing.assistantDisplayName(id: assistantID, rawName: localizedName)
        description = CoworkUserFacing.assistantDisplayDescription(
            id: assistantID,
            rawDescription: localizedDescription
        )
        rules = CoworkUserFacing.sanitizeFreeText(detail.rules.resolvedContent)
        if rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rules = await cowork.loadAssistantRule(assistantID: assistantID)
        }
        recommendedPromptsText = detail.prompts.localizedRecommended(locale: locale).joined(separator: "\n")
        enabled = detail.state.enabled
        initialEnabled = detail.state.enabled
    }

    private func saveEnabledOnly(_ newValue: Bool) async {
        guard newValue != initialEnabled else { return }
        isSaving = true
        defer { isSaving = false }
        await cowork.saveAssistant(
            id: assistantID,
            source: source,
            name: name,
            description: description,
            rules: rules,
            recommendedPrompts: recommendedPromptsText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            enabled: newValue
        )
        initialEnabled = newValue
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let prompts = recommendedPromptsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        await cowork.saveAssistant(
            id: assistantID,
            source: source,
            name: name,
            description: description,
            rules: rules,
            recommendedPrompts: prompts,
            enabled: enabled
        )
        dismiss()
    }
}

struct CoworkSkillsHubView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var selectedAssistantID = "cowork"
    @State private var ruleText = ""
    @State private var expandedSkillID: String?
    @State private var skillContents: [String: String] = [:]
    @State private var ruleSaved = false

    private var selectedAssistant: CoworkAssistant? {
        cowork.assistants.first(where: { $0.id == selectedAssistantID })
    }

    private var rulesEditable: Bool {
        selectedAssistant?.isBuiltin != true
    }

    private var hubSkills: [CoworkSkill] {
        var seen = Set<String>()
        return cowork.availableSkills.filter { skill in
            seen.insert(skill.displayTitle.lowercased()).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PrismDropdownFieldRequired(
                label: L10n.assistantLabel,
                selection: $selectedAssistantID,
                options: cowork.assistants.map {
                    PrismDropdownOption(value: $0.id, title: $0.displayName, subtitle: $0.displayBackendType)
                },
                leadingIcon: "sparkles"
            )
            .onChange(of: selectedAssistantID) { _ in Task { await loadRule() } }

            Text(L10n.assistantRuleLabel).font(.ps(11, weight: .semibold))
            if !rulesEditable {
                Text(L10n.assistantRulesReadOnlyHelp)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            TextEditor(text: $ruleText)
                .font(.ps(11, design: .monospaced))
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(PrismTheme.surfaceMuted.opacity(0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PrismTheme.borderSubtle, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(!rulesEditable)

            HStack {
                Button(L10n.reload) { Task { await loadRule() } }.buttonStyle(PrismHandButtonStyle())
                Spacer()
                if ruleSaved {
                    Text(L10n.saved)
                        .font(.ps(10, weight: .semibold))
                        .foregroundStyle(PrismTheme.signalAllow)
                }
                Button(L10n.saveRule) {
                    Task {
                        await cowork.saveAssistantRule(assistantID: selectedAssistantID, content: ruleText)
                        if rulesEditable {
                            ruleText = CoworkUserFacing.sanitizeFreeText(ruleText)
                            ruleSaved = true
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            ruleSaved = false
                        }
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
                .help(L10n.saveRuleKeepsOpen)
                .disabled(!rulesEditable)
            }

            Divider().opacity(0.2)

            Text(L10n.availableSkills).font(.ps(11, weight: .semibold))
            ForEach(hubSkills) { skill in
                skillRow(skill)
            }
        }
        .padding(.top, 8)
        .task { await loadRule() }
    }

    @ViewBuilder
    private func skillRow(_ skill: CoworkSkill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if expandedSkillID == skill.id {
                    expandedSkillID = nil
                } else {
                    expandedSkillID = skill.id
                    Task { await loadSkillContent(skill) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedSkillID == skill.id ? "chevron.down" : "chevron.right")
                        .font(.ps(9, weight: .bold))
                        .foregroundStyle(PrismTheme.textTertiary)
                    Text(skill.displayTitle)
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.textSecondary)
                    if let description = skill.displayDetail {
                        Text(description)
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(PrismHandButtonStyle())

            if expandedSkillID == skill.id {
                ScrollView {
                    Text(CoworkUserFacing.skillContentDisplay(skillContents[skill.id] ?? L10n.loading))
                        .font(.ps(10, design: .monospaced))
                        .foregroundStyle(PrismTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .padding(8)
                .background(PrismTheme.surfaceMuted.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func loadSkillContent(_ skill: CoworkSkill) async {
        guard skillContents[skill.id] == nil else { return }
        skillContents[skill.id] = await cowork.loadBuiltinSkillContent(skill)
    }

    private func loadRule() async {
        ruleText = await cowork.loadAssistantRule(assistantID: selectedAssistantID)
    }
}
