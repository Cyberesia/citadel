import Foundation

/// Maps CoworkCore / upstream identifiers to Citadel-facing copy. Backend ids stay unchanged.
enum CoworkUserFacing {

    // MARK: - Agent permissions

    enum PermissionMode: String, CaseIterable, Identifiable, Sendable {
        case `default`
        case acceptEdits
        case bypassPermissions
        case plan

        var id: String { rawValue }

        var title: String {
            switch self {
            case .default: return L10n.permStandard
            case .acceptEdits: return L10n.permAutoEdits
            case .bypassPermissions: return L10n.permFullAuto
            case .plan: return L10n.permPlanOnly
            }
        }

        var detail: String {
            switch self {
            case .default: return L10n.permStandardDetail
            case .acceptEdits: return L10n.permAutoEditsDetail
            case .bypassPermissions: return L10n.permFullAutoDetail
            case .plan: return L10n.permPlanDetail
            }
        }

        static func from(stored: String) -> PermissionMode {
            PermissionMode(rawValue: stored) ?? .default
        }
    }

    // MARK: - Skills

    private static let skillTitles: [String: String] = [
        "aionui-config": "Keep configuration",
        "skill-creator": "Skill creator",
        "cron": "Scheduled tasks",
        "officecli": "Office automation",
        "story-roleplay": "Story roleplay",
        "weixin-file-send": "kDrive file share",
        "x-recruiter": "Infomaniak Newsletter · hiring",
        "xiaohongshu-recruiter": "Infomaniak Newsletter · hiring",
        "openclaw-setup": "Remote agent setup",
        "morph-ppt": "Morph PPT",
        "morph-ppt-3d": "Morph PPT 3D",
        "beautiful-mermaid": "Mermaid",
        "troubleshooting": "Troubleshooting",
        "webui-public": "WebUI public",
        "webui-setup": "WebUI setup",
        "pdf": "PDF",
    ]

    private static let skillDetails: [String: String] = [
        "aionui-config": L10n.skillDetailCoworkConfig,
        "skill-creator": L10n.skillDetailSkillCreator,
        "cron": L10n.skillDetailScheduledTasks,
        "officecli": L10n.skillDetailOfficeAutomation,
        "story-roleplay": L10n.skillDetailStoryRoleplay,
        "weixin-file-send": L10n.skillDetailKDriveShare,
        "x-recruiter": L10n.skillDetailNewsletterHiring,
        "xiaohongshu-recruiter": L10n.skillDetailNewsletterHiring,
        "openclaw-setup": L10n.skillDetailRemoteAgentSetup,
        "morph-ppt": L10n.skillDetailMorphPPT,
        "morph-ppt-3d": L10n.skillDetailMorphPPT3D,
        "beautiful-mermaid": L10n.skillDetailMermaid,
        "mermaid": L10n.skillDetailMermaid,
        "moltbook": L10n.skillDetailMoltbook,
        "troubleshooting": L10n.skillDetailTroubleshooting,
        "webui-public": L10n.skillDetailWebUIPublic,
        "webui-setup": L10n.skillDetailWebUISetup,
        "pdf": L10n.skillDetailPDF,
    ]

    static func skillTitle(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Skill" }
        let lower = trimmed.lowercased()
        if let known = skillTitles[lower] { return known }
        if lower.contains("weixin") || lower.contains("wechat") { return "kDrive file share" }
        if lower.contains("moltbook") || lower.contains("molt-") {
            return L10n.assistantNameAgentSocial
        }
        if lower.contains("xiaohongshu") || lower == "x-recruiter" || lower.hasPrefix("x-recruiter") {
            return "Infomaniak Newsletter · hiring"
        }
        if lower.contains("baidu") { return "Infomaniak kAI search" }
        if lower.contains("dingtalk") || lower.contains("lark") || lower.contains("feishu") {
            return "Infomaniak kChat"
        }

        var slug = trimmed
        for prefix in ["aionui-", "aion-", "cowork-"] {
            if slug.lowercased().hasPrefix(prefix) {
                slug = String(slug.dropFirst(prefix.count))
                break
            }
        }
        slug = slug.replacingOccurrences(of: "_", with: "-")
        let title = slug
            .split(separator: "-")
            .map { part in
                let s = String(part)
                if s.count <= 3 { return s.uppercased() }
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
        return localizeRegionalServices(title)
    }

    static func skillDetail(_ skill: CoworkSkill) -> String? {
        if let known = knownSkillDetail(name: skill.name) {
            return known
        }
        let description = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return nil }
        let sanitized = localizeRegionalServices(sanitizeFreeText(description))
        guard !containsCJKScript(sanitized) else { return nil }
        return sanitized
    }

    static func skillContentDisplay(_ content: String) -> String {
        let sanitized = localizeRegionalServices(sanitizeFreeText(content))
        guard !containsCJKScript(sanitized) else {
            return L10n.skillContentUnavailable
        }
        return sanitized
    }

    static func mcpServerDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "MCP server" }
        return localizeRegionalServices(sanitizeFreeText(trimmed))
    }

    static func mcpServerDisplayDescription(_ raw: String?) -> String? {
        let description = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return nil }
        let sanitized = localizeRegionalServices(sanitizeFreeText(description))
        guard !containsCJKScript(sanitized) else { return nil }
        return sanitized
    }

    private static func knownSkillDetail(name: String) -> String? {
        let lower = name.lowercased()
        if let known = skillDetails[lower] { return known }
        if lower.contains("weixin") || lower.contains("wechat") {
            return L10n.skillDetailKDriveShare
        }
        if lower.contains("xiaohongshu") || lower.contains("x-recruiter") {
            return L10n.skillDetailNewsletterHiring
        }
        if lower.contains("officecli") {
            return officecliSkillDetail(lower)
        }
        if lower.contains("morph-ppt-3d") || lower.contains("morph_ppt_3d") {
            return L10n.skillDetailMorphPPT3D
        }
        if lower.contains("morph-ppt") || lower.contains("morph_ppt") {
            return L10n.skillDetailMorphPPT
        }
        if lower.contains("mermaid") { return L10n.skillDetailMermaid }
        if lower.contains("moltbook") || lower.contains("molt-") {
            return L10n.skillDetailMoltbook
        }
        if lower.contains("webui-public") || lower.contains("webui_public") {
            return L10n.skillDetailWebUIPublic
        }
        if lower.contains("webui-setup") || lower.contains("webui_setup") {
            return L10n.skillDetailWebUISetup
        }
        return nil
    }

    private static func officecliSkillDetail(_ lower: String) -> String {
        if lower.contains("pptx") || lower.contains("ppt") || lower.contains("pitch-deck") {
            return L10n.skillDetailOfficePPT
        }
        if lower.contains("xlsx") || lower.contains("financial") || lower.contains("dashboard") {
            return L10n.skillDetailOfficeExcel
        }
        if lower.contains("docx") || lower.contains("word") || lower.contains("academic") {
            return L10n.skillDetailOfficeWord
        }
        return L10n.skillDetailOfficeAutomation
    }

    private static func containsCJKScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Models

    struct ModelDisplay: Sendable {
        let alias: String
        let technical: String?
        let provider: String
        var summary: String {
            var parts = [alias]
            if let technical, !technical.isEmpty, technical.caseInsensitiveCompare(alias) != .orderedSame {
                parts.append(technical)
            }
            if !provider.isEmpty { parts.append(provider) }
            return parts.joined(separator: " · ")
        }
    }

    static func mlxCatalogMatch(_ rawModel: String) -> CoworkMLXModelInfo? {
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = CoworkMLXModelCatalog.models.first(where: { $0.id == trimmed }) { return exact }
        let suffix = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return CoworkMLXModelCatalog.models.first { info in
            info.id == trimmed
                || info.id.hasSuffix("/\(suffix)")
                || trimmed.hasSuffix(info.id)
                || info.id.split(separator: "/").last.map(String.init) == suffix
        }
    }

    static func modelLabel(providerID: String?, rawModel: String) -> String {
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown model" }
        if let mlx = mlxCatalogMatch(trimmed) { return mlx.displayName }

        let lower = trimmed.lowercased()
        if lower.contains("qwen3.5") || lower.contains("qwen3-") || lower.hasPrefix("qwen3") { return "Qwen 3" }
        if lower.contains("deepseek") { return "DeepSeek" }
        if lower.contains("llama") { return "Llama" }
        if lower.contains("mistral") { return "Mistral" }
        if lower.contains("gemma") { return "Gemma" }
        if lower.contains("gpt-4") { return "GPT-4" }
        if lower.contains("gpt-3") { return "GPT-3.5" }
        if lower.contains("claude") { return "Claude" }
        if lower.contains("gemini") { return "Gemini" }

        return trimmed
    }

    static func modelTechnicalName(providerID: String?, rawModel: String) -> String? {
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let mlx = mlxCatalogMatch(trimmed) { return mlx.detailSubtitle }
        let alias = modelLabel(providerID: providerID, rawModel: trimmed)
        if alias.caseInsensitiveCompare(trimmed) == .orderedSame { return nil }
        return trimmed
    }

    static func modelProviderLabel(_ providerID: String, providers: [CoworkProvider] = []) -> String {
        if let provider = providers.first(where: { $0.id == providerID }) {
            return providerLabel(platform: provider.platform, name: provider.name, providerID: providerID)
        }
        return providerLabel(platform: providerID, name: "", providerID: providerID)
    }

    static func providerLabel(platform: String, name: String, providerID: String) -> String {
        switch platform.lowercased() {
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "gemini", "google": return "Google Gemini"
        case "xai": return "xAI"
        case "infomaniak": return "Infomaniak kAI"
        case "openrouter": return "OpenRouter"
        case "mlx", "mlx_native", "mlx-native": return "Native MLX"
        case "ollama": return "Ollama"
        case "custom":
            let lowerName = name.lowercased()
            if lowerName.contains("ollama") { return "Ollama" }
            if lowerName.contains("lm studio") || lowerName.contains("lmstudio") { return "LM Studio" }
            if lowerName.contains("mlx") { return "Native MLX" }
            return name.isEmpty ? "Custom provider" : name
        default:
            let lowerID = providerID.lowercased()
            if lowerID.contains("ollama") { return "Ollama" }
            if lowerID.contains("mlx") { return "Native MLX" }
            if lowerID.contains("openai") { return "OpenAI" }
            if lowerID.contains("anthropic") { return "Anthropic" }
            if lowerID.contains("gemini") || lowerID.contains("google") { return "Google Gemini" }
            return name.isEmpty
                ? platform.replacingOccurrences(of: "_", with: " ").capitalized
                : name
        }
    }

    static func modelDisplay(
        providerID: String?,
        rawModel: String,
        providers: [CoworkProvider] = []
    ) -> ModelDisplay {
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = modelLabel(providerID: providerID, rawModel: trimmed)
        let technical = modelTechnicalName(providerID: providerID, rawModel: trimmed)
        let provider = resolveProviderLabel(providerID: providerID, rawModel: trimmed, providers: providers)
        return ModelDisplay(alias: alias, technical: technical, provider: provider)
    }

    /// Provider label that respects MLX catalog ids even when selection state is stale.
    static func resolveProviderLabel(
        providerID: String?,
        rawModel: String,
        providers: [CoworkProvider] = []
    ) -> String {
        if mlxCatalogMatch(rawModel) != nil { return "Native MLX" }

        if let providerID,
           let provider = providers.first(where: { $0.id == providerID }) {
            if provider.name.lowercased().contains("mlx")
                || provider.baseURL.contains(":8765") {
                return "Native MLX"
            }
            return providerLabel(platform: provider.platform, name: provider.name, providerID: providerID)
        }

        if let providerID, !providerID.isEmpty {
            return modelProviderLabel(providerID, providers: providers)
        }
        return ""
    }

    /// Legacy single-label helper.
    static func modelProviderLabel(_ providerID: String) -> String {
        modelProviderLabel(providerID, providers: [])
    }

    // MARK: - Assistants

    static func assistantDisplayName(id: String, rawName: String) -> String {
        switch normalizedAssistantID(id) {
        case "moltbook": return L10n.assistantNameAgentSocial
        default: break
        }
        return humanizeBrandedTerms(sanitizeBrandName(rawName))
    }

    static func assistantDisplayDescription(id: String, rawDescription: String) -> String {
        switch normalizedAssistantID(id) {
        case "moltbook": return L10n.assistantDescAgentSocial
        default: break
        }
        let sanitized = humanizeBrandedTerms(sanitizeFreeText(rawDescription))
        guard !containsCJKScript(sanitized) else { return "" }
        return sanitized
    }

    static func assistantBuiltinOverview(id: String) -> String {
        switch normalizedAssistantID(id) {
        case "moltbook": return L10n.assistantOverviewAgentSocial
        default: return L10n.assistantBuiltinGenericOverview
        }
    }

    private static func normalizedAssistantID(_ id: String) -> String {
        id.replacingOccurrences(of: "builtin-", with: "")
    }

    private static func sanitizeBrandName(_ raw: String) -> String {
        localizeRegionalServices(
            raw
                .replacingOccurrences(of: "AionUi", with: "Citadel Keep", options: .caseInsensitive)
                .replacingOccurrences(of: "AionUI", with: "Citadel Keep", options: .caseInsensitive)
                .replacingOccurrences(of: "Aion", with: "Keep", options: .caseInsensitive)
                .replacingOccurrences(of: "CoworkCore", with: "Keep engine", options: .caseInsensitive)
                .replacingOccurrences(of: "Cowork", with: "Keep", options: .caseInsensitive)
        )
    }

    private static func humanizeBrandedTerms(_ text: String) -> String {
        var result = sanitizeBrandName(text)
        let replacements: [(String, String)] = [
            ("moltbook assistant", L10n.assistantNameAgentSocial),
            ("moltbook", L10n.assistantNameAgentSocial),
            ("Moltbook", L10n.assistantNameAgentSocial),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        return result
    }

    private static let assistantSummaries: [String: String] = [
        "cowork": "General-purpose agent for files, code, images, and everyday tasks.",
        "aionui-assistant": "Default Citadel Keep agent with workspace tools and skills.",
        "morph-ppt-3d": "Build PowerPoint decks with 3D morph transitions between slides.",
        "morph-ppt": "Create polished presentations with smooth slide morph animations.",
        "ppt-creator": "Draft slide outlines, speaker notes, and export-ready PPT content.",
        "excel-creator": "Spreadsheets, formulas, charts, and data cleanup in Excel.",
        "word-creator": "Long-form documents, reports, and formatted Word files.",
        "word-form-creator": "Fillable forms and structured Word templates.",
        "dashboard-creator": "Interactive dashboards and KPI summaries from your data.",
        "financial-model-creator": "Spreadsheet models, scenarios, and financial projections.",
        "pitch-deck-creator": "Investor-ready pitch decks with narrative flow.",
        "academic-paper": "Research papers with citations, structure, and revision passes.",
        "beautiful-mermaid": "Diagrams and flowcharts using Mermaid syntax.",
        "ui-ux-pro-max": "UI mockups, UX copy, and design-system friendly layouts.",
        "story-roleplay": "Creative writing, characters, and interactive story play.",
        "planning-with-files": "Break big goals into plans tied to files in your workspace.",
        "openclaw-setup-expert": "Configure OpenClaw agents, tools, and integrations.",
        "social-job-publisher": "Job posts and social copy for hiring workflows.",
        "human-3-coach": "Coaching conversations using the HUMAN 3.0 framework.",
        "3d-game": "Prototype simple 3D game ideas, assets, and design docs.",
        "moltbook": "Agent social network — posts, comments, and communities for AI agents.",
        "bare:632f31d2": "Terminal-first Cowork CLI workflows.",
        "claude-code": "ACP bridge for Claude Code style coding sessions.",
    ]

    static func assistantSummary(id: String, name: String) -> String {
        if normalizedAssistantID(id) == "moltbook" { return L10n.assistantDescAgentSocial }
        if let known = assistantSummaries[id] { return known }
        if let known = assistantSummaries[normalizedAssistantID(id)] { return known }

        let lower = name.lowercased()
        if lower.contains("moltbook") || lower.contains("molt-") {
            return L10n.assistantDescAgentSocial
        }
        if lower.contains("ppt") || lower.contains("deck") {
            return "Presentation workflows — outlines, slides, and exports."
        }
        if lower.contains("excel") || lower.contains("spreadsheet") {
            return "Spreadsheet creation, formulas, and data tasks."
        }
        if lower.contains("word") {
            return "Document drafting and formatting in Word."
        }
        if lower.contains("3d") {
            return "3D visuals, scenes, and related creative output."
        }
        if lower.contains("image") {
            return "Generate or edit images for your project."
        }
        if lower.contains("folder") || lower.contains("file") {
            return "Organize, search, and transform files in your workspace."
        }
        return "Specialist agent — pick this for focused \(name) tasks."
    }

    // MARK: - General copy

    /// Rewrites China-specific product names to Swiss / Infomaniak equivalents for Citadel UI.
    static func localizeRegionalServices(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("WeChat file send", "kDrive file share"),
            ("WeChat Pay", "TWINT"),
            ("WeChat", "Infomaniak kChat"),
            ("Weixin", "Infomaniak kChat"),
            ("微信", "Infomaniak kChat"),
            ("Xiaohongshu Recruiter", "Infomaniak Newsletter · hiring"),
            ("Xiaohongshu", "Swiss social campaigns"),
            ("小红书", "Swiss social campaigns"),
            ("Baidu", "Infomaniak kAI"),
            ("百度", "Infomaniak kAI"),
            ("DingTalk", "Infomaniak kMeet"),
            ("钉钉", "Infomaniak kMeet"),
            ("Lark", "Infomaniak kChat"),
            ("Feishu", "Infomaniak kChat"),
            ("飞书", "Infomaniak kChat"),
            ("Alipay", "TWINT"),
            ("支付宝", "TWINT"),
            ("Tencent", "Infomaniak"),
            ("腾讯", "Infomaniak"),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        return result
    }

    static func sanitizeFreeText(_ text: String) -> String {
        localizeRegionalServices(
            text
                .replacingOccurrences(of: "AionUi", with: "Keep", options: .caseInsensitive)
                .replacingOccurrences(of: "AionUI", with: "Keep", options: .caseInsensitive)
                .replacingOccurrences(of: "AIonUI", with: "Keep", options: .caseInsensitive)
                .replacingOccurrences(of: "Aion", with: "Keep", options: .caseInsensitive)
                .replacingOccurrences(of: "CoworkCore", with: "Keep engine", options: .caseInsensitive)
                .replacingOccurrences(of: "Cowork", with: "Keep", options: .caseInsensitive)
        )
    }
}

extension CoworkSkill {
    var displayTitle: String { CoworkUserFacing.skillTitle(name) }
    var displayDetail: String? { CoworkUserFacing.skillDetail(self) }
}

extension CoworkMcpServer {
    var displayName: String { CoworkUserFacing.mcpServerDisplayName(name) }
    var displayDescription: String? { CoworkUserFacing.mcpServerDisplayDescription(description) }
}

extension CoworkMcpDetectedServer {
    var displayName: String { CoworkUserFacing.mcpServerDisplayName(name) }
    var displayDescription: String? { CoworkUserFacing.mcpServerDisplayDescription(description) }
}

extension CoworkAssistant {
    var displaySummary: String {
        CoworkUserFacing.assistantSummary(id: id, name: displayName)
    }
}

extension CoworkConversation {
    func modelDisplay(providers: [CoworkProvider]) -> CoworkUserFacing.ModelDisplay? {
        guard let ref = model else { return nil }
        return CoworkUserFacing.modelDisplay(
            providerID: ref.providerID,
            rawModel: ref.model,
            providers: providers
        )
    }

    var displayModelLabel: String? {
        modelDisplay(providers: [])?.alias
    }

    var displayModelSummary: String? {
        modelDisplay(providers: [])?.summary
    }

    var displayModelProviderLabel: String? {
        guard let ref = model else { return nil }
        let label = CoworkUserFacing.modelProviderLabel(ref.providerID)
        return label.isEmpty ? nil : label
    }

    var displayUpdatedLabel: String? {
        guard let updatedAt else { return nil }
        let date = Date(timeIntervalSince1970: updatedAt / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
