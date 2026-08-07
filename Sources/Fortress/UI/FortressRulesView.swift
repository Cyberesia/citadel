import SwiftUI

/// Fortress-native rules studio — create, suggest from activity, fine-tune.
struct FortressRulesView: View {
    @EnvironmentObject var fortress: FortressViewModel
    @State private var search = ""
    @State private var filter: RuleFilter = .all
    @State private var selected: Rule?
    @State private var showComposer = false
    @State private var composerDraft = RuleComposerDraft()
    @State private var showSuggestions = true

    enum RuleFilter: String, CaseIterable, Identifiable {
        case all, allow, deny, ask, temporary
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return L10n.all
            case .allow: return L10n.allow
            case .deny: return L10n.deny
            case .ask: return L10n.ask
            case .temporary: return L10n.temporary
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(PrismTheme.surfaceMuted.opacity(0.4))
            Divider().opacity(0.3)
            mainList
            Divider().opacity(0.3)
            detailPane
                .frame(width: 300)
                .background(PrismTheme.surfaceMuted.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { fortress.bridge.refreshRules() }
        .sheet(isPresented: $showComposer) {
            RuleComposerSheet(
                draft: $composerDraft,
                helperOnline: fortress.helperConnected,
                onSave: { draft in
                    let rule = draft.makeRule()
                    fortress.bridge.addRule(rule)
                    selected = rule
                    showComposer = false
                },
                onCancel: { showComposer = false }
            )
            .frame(minWidth: 480, minHeight: 420)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.fortressRules)
                .font(.ps(13, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
                .padding(14)

            ForEach(RuleFilter.allCases) { f in
                filterRow(f)
            }

            Divider().opacity(0.3).padding(.vertical, 8)

            Text(L10n.fromActivity)
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textTertiary)
                .padding(.horizontal, 14)

            Toggle(isOn: $showSuggestions) {
                Text(L10n.showSuggestions)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            .toggleStyle(PrismHandToggleStyle(kind: .checkbox))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .prismClickable()

            Spacer()

            if !fortress.helperConnected {
                Text(L10n.helperRulesOffline)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .padding(14)
            }
        }
    }

    private func filterRow(_ f: RuleFilter) -> some View {
        Button {
            filter = f
        } label: {
            HStack {
                Text(f.label)
                    .font(.ps(12, weight: filter == f ? .semibold : .medium))
                Spacer()
                Text("\(count(for: f))")
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            .foregroundStyle(PrismTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(filter == f ? PrismTheme.accent.opacity(0.16) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismHandButtonStyle())
    }

    // MARK: - Main

    private var mainList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PrismTheme.textTertiary)
                    TextField(L10n.searchRules, text: $search)
                        .textFieldStyle(.plain)
                        .font(.ps(12))
                }
                .padding(8)
                .background(PrismTheme.surface.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    composerDraft = RuleComposerDraft()
                    showComposer = true
                } label: {
                    Label(L10n.newRule, systemImage: "plus")
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PrismTheme.accentSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(PrismHandButtonStyle())
            }
            .padding(12)

            if showSuggestions && !suggestions.isEmpty {
                suggestionsStrip
            }

            Divider().opacity(0.25)

            if filteredRules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
        }
    }

    private var suggestionsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(PrismTheme.accent)
                Text(L10n.suggestedFromActivity)
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        suggestionCard(suggestion)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 10)
    }

    private func suggestionCard(_ s: RuleSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.title)
                .font(.ps(12, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
                .lineLimit(1)
            Text(s.subtitle)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
                .lineLimit(2)
            HStack(spacing: 6) {
                PrismActionChip(title: L10n.allow, systemImage: "checkmark", kind: .allow) {
                    fortress.bridge.addRule(s.asRule(action: .allow))
                }
                PrismActionChip(title: L10n.deny, systemImage: "xmark", kind: .deny) {
                    fortress.bridge.addRule(s.asRule(action: .deny))
                }
            }
        }
        .padding(10)
        .frame(width: 200, alignment: .leading)
        .background(PrismTheme.surface.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PrismTheme.borderSubtle, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.ps(28))
                .foregroundStyle(PrismTheme.textTertiary)
            Text(L10n.noRulesYet)
                .font(.ps(15, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
            Text(L10n.noRulesHint)
                .font(.ps(12))
                .foregroundStyle(PrismTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                composerDraft = RuleComposerDraft()
                showComposer = true
            } label: {
                Text(L10n.createFirstRule)
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(PrismTheme.accentGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(PrismHandButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ruleRow(_ rule: Rule) -> some View {
        Button {
            selected = rule
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(actionColor(rule.action))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.processName ?? rule.processBundleId ?? L10n.anyProcess)
                        .font(.ps(12, weight: .medium))
                        .foregroundStyle(PrismTheme.textPrimary)
                        .lineLimit(1)
                    Text(ruleSummary(rule))
                        .font(.ps(10))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(actionLabel(rule.action))
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(actionColor(rule.action))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected?.id == rule.id ? PrismTheme.accent.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PrismHandButtonStyle())
    }

    // MARK: - Detail

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selected == nil ? L10n.inspector : L10n.ruleDetail)
                .font(.ps(16, weight: .bold))
                .foregroundStyle(PrismTheme.textPrimary)

            if let rule = selected {
                detailRows(rule)
                Spacer()
                VStack(spacing: 8) {
                    PrismActionChip(
                        title: rule.enabled ? L10n.disable : L10n.enable,
                        systemImage: rule.enabled ? "pause.fill" : "play.fill",
                        kind: .accent
                    ) {
                        toggle(rule)
                    }
                    PrismActionChip(title: L10n.duplicateEdit, systemImage: "plus.square.on.square", kind: .neutral) {
                        composerDraft = RuleComposerDraft(from: rule)
                        showComposer = true
                    }
                    PrismActionChip(title: L10n.remove, systemImage: "trash", kind: .deny) {
                        fortress.bridge.removeRule(id: rule.id)
                        if selected?.id == rule.id { selected = nil }
                    }
                }
            } else {
                Text(L10n.inspectorEmptyHint)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
                Spacer()
            }
        }
        .padding(14)
    }

    private func detailRows(_ rule: Rule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            field(L10n.process, rule.processName ?? L10n.any)
            if let path = rule.processPath, !path.isEmpty { field(L10n.pathLabel, path) }
            if let bid = rule.processBundleId, !bid.isEmpty { field("Bundle", bid) }
            field(L10n.host, rule.remoteHost ?? rule.remoteIP ?? L10n.any)
            if let port = rule.remotePort, port > 0 { field(L10n.port, "\(port)") }
            field(L10n.action, actionLabel(rule.action))
            field(L10n.scope, scopeLabel(rule.scope))
            field(L10n.direction, rule.direction.rawValue)
            field(L10n.priority, "\(rule.priority)")
            field(L10n.status, rule.enabled ? L10n.enabled : L10n.disabled)
            if let notes = rule.notes, !notes.isEmpty { field(L10n.notes, notes) }
        }
        .padding(10)
        .background(PrismTheme.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func field(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(v)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textPrimary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Data

    private var filteredRules: [Rule] {
        var list = fortress.bridge.rules
        switch filter {
        case .all: break
        case .allow: list = list.filter { $0.action == .allow }
        case .deny: list = list.filter { $0.action == .deny }
        case .ask: list = list.filter { $0.action == .ask }
        case .temporary: list = list.filter(\.temporary)
        }
        if !search.isEmpty {
            list = list.filter {
                ($0.processName ?? "").localizedCaseInsensitiveContains(search)
                    || ($0.remoteHost ?? "").localizedCaseInsensitiveContains(search)
                    || ($0.remoteIP ?? "").localizedCaseInsensitiveContains(search)
                    || ($0.processBundleId ?? "").localizedCaseInsensitiveContains(search)
            }
        }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    private func count(for f: RuleFilter) -> Int {
        let list = fortress.bridge.rules
        switch f {
        case .all: return list.count
        case .allow: return list.filter { $0.action == .allow }.count
        case .deny: return list.filter { $0.action == .deny }.count
        case .ask: return list.filter { $0.action == .ask }.count
        case .temporary: return list.filter(\.temporary).count
        }
    }

    private var suggestions: [RuleSuggestion] {
        var out: [RuleSuggestion] = []
        let existingHosts = Set(fortress.bridge.rules.compactMap(\.remoteHost))
        let existingFamilies = Set(fortress.bridge.rules.compactMap(\.processName))

        for family in fortress.topFamilies.prefix(4) {
            if existingFamilies.contains(family.label) { continue }
            out.append(RuleSuggestion(
                id: "fam-\(family.id)",
                title: family.label,
                subtitle: L10n.appFamilyStreams(family.connectionCount),
                processName: family.label,
                remoteHost: nil,
                scope: .process
            ))
        }
        for dest in fortress.topDestinations.prefix(4) {
            guard let stream = fortress.stream(for: dest.id) else { continue }
            let host = stream.remoteHost.isEmpty ? stream.remoteIP : stream.remoteHost
            if existingHosts.contains(host) { continue }
            out.append(RuleSuggestion(
                id: "dest-\(dest.id)",
                title: dest.label,
                subtitle: "\(stream.process.familyName) → \(host)",
                processName: stream.process.name,
                remoteHost: host,
                scope: .domain
            ))
        }
        return Array(out.prefix(6))
    }

    private func ruleSummary(_ rule: Rule) -> String {
        let host = rule.remoteHost ?? rule.remoteIP ?? L10n.anyHost
        return "\(actionLabel(rule.action)) · \(host)"
    }

    private func actionLabel(_ action: RuleAction) -> String {
        switch action {
        case .allow: return L10n.allow
        case .deny: return L10n.deny
        case .ask: return L10n.ask
        }
    }

    private func scopeLabel(_ scope: RuleScope) -> String {
        switch scope {
        case .domain: return L10n.domain
        case .process: return L10n.process
        case .ip: return "IP"
        case .port: return L10n.port
        case .any: return L10n.any
        }
    }

    private func actionColor(_ action: RuleAction) -> Color {
        switch action {
        case .allow: return PrismTheme.signalAllow
        case .deny: return PrismTheme.signalDeny
        case .ask: return PrismTheme.accentSecondary
        }
    }

    private func toggle(_ rule: Rule) {
        var copy = rule
        copy.enabled.toggle()
        fortress.bridge.removeRule(id: rule.id)
        fortress.bridge.addRule(copy)
        selected = copy
    }
}

// MARK: - Suggestion model

struct RuleSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let processName: String?
    let remoteHost: String?
    let scope: RuleScope

    func asRule(action: RuleAction) -> Rule {
        Rule(
            processName: processName,
            remoteHost: remoteHost,
            direction: .outgoing,
            action: action,
            scope: scope,
            priority: 100,
            notes: L10n.suggestedFromFortress
        )
    }
}

// MARK: - Composer

struct RuleComposerDraft {
    var processName = ""
    var processBundleId = ""
    var remoteHost = ""
    var remotePort = ""
    var action: RuleAction = .deny
    var scope: RuleScope = .domain
    var temporary = false
    var notes = ""

    init() {}

    init(from rule: Rule) {
        processName = rule.processName ?? ""
        processBundleId = rule.processBundleId ?? ""
        remoteHost = rule.remoteHost ?? rule.remoteIP ?? ""
        remotePort = rule.remotePort.map(String.init) ?? ""
        action = rule.action
        scope = rule.scope
        temporary = rule.temporary
        notes = rule.notes ?? ""
    }

    func makeRule() -> Rule {
        Rule(
            processBundleId: processBundleId.isEmpty ? nil : processBundleId,
            processName: processName.isEmpty ? nil : processName,
            remoteHost: remoteHost.isEmpty ? nil : remoteHost,
            remotePort: Int(remotePort),
            direction: .outgoing,
            action: action,
            scope: scope,
            priority: 100,
            notes: notes.isEmpty ? L10n.createdInFortressRules : notes,
            temporary: temporary,
            expiresAt: temporary ? Date().addingTimeInterval(3600) : nil
        )
    }
}

struct RuleComposerSheet: View {
    @Binding var draft: RuleComposerDraft
    let helperOnline: Bool
    let onSave: (RuleComposerDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.newRule)
                .font(.ps(18, weight: .bold))
                .foregroundStyle(PrismTheme.textPrimary)

            if !helperOnline {
                Text(L10n.helperRuleQueued)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.accentSecondary)
            }

            formField(L10n.processName, text: $draft.processName, placeholder: L10n.processNameExample)
            formField(L10n.bundleID, text: $draft.processBundleId, placeholder: L10n.optional)
            formField(L10n.remoteHostIP, text: $draft.remoteHost, placeholder: L10n.remoteHostExample)
            formField(L10n.port, text: $draft.remotePort, placeholder: L10n.optional)

            HStack {
                Text(L10n.action)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $draft.action) {
                    Text(L10n.allow).tag(RuleAction.allow)
                    Text(L10n.deny).tag(RuleAction.deny)
                    Text(L10n.ask).tag(RuleAction.ask)
                }
                .pickerStyle(.segmented)
                .prismClickable()
            }

            HStack {
                Text(L10n.scope)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $draft.scope) {
                    Text(L10n.domain).tag(RuleScope.domain)
                    Text(L10n.process).tag(RuleScope.process)
                    Text("IP").tag(RuleScope.ip)
                    Text(L10n.any).tag(RuleScope.any)
                }
                .labelsHidden()
                .prismClickable()
            }

            Toggle(L10n.temporary1h, isOn: $draft.temporary)
                .font(.ps(12))
                .prismClickable()

            formField(L10n.notes, text: $draft.notes, placeholder: L10n.optional)

            Spacer()

            HStack {
                Button(L10n.cancel, action: onCancel)
                    .buttonStyle(PrismHandButtonStyle())
                    .foregroundStyle(PrismTheme.textSecondary)
                Spacer()
                Button {
                    onSave(draft)
                } label: {
                    Text(L10n.saveRule)
                        .font(.ps(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(PrismTheme.accentGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(draft.processName.isEmpty && draft.remoteHost.isEmpty && draft.processBundleId.isEmpty)
            }
        }
        .padding(22)
        .background(PrismTheme.dominant)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textTertiary)
                .frame(width: 100, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.ps(12))
                .padding(8)
                .background(PrismTheme.surface.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
