import Foundation

/// Localized help content for Keep. Add a language by putting another key in `title` / `body`
/// (e.g. `"de": "…"`) — `resolved` falls back to English, then the first available string.
struct KeepHelpArticle: Identifiable, Hashable, Sendable {
    let id: String
    /// Topic group for browsing (stable English key; localized via `KeepHelpCategory`).
    let category: KeepHelpCategory
    /// Related Keep pages — used to surface contextual articles.
    let modes: [String]
    let title: [String: String]
    let body: [String: String]
    let keywords: [String]

    func resolvedTitle(locale: CitadelLocale = .current) -> String {
        Self.resolve(title, locale: locale)
    }

    func resolvedBody(locale: CitadelLocale = .current) -> String {
        Self.resolve(body, locale: locale)
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let hay = ([resolvedTitle(), resolvedBody()] + keywords + Array(title.values) + Array(body.values))
            .joined(separator: " ")
            .lowercased()
        return q.split(whereSeparator: \.isWhitespace).allSatisfy { hay.contains($0) }
    }

    private static func resolve(_ map: [String: String], locale: CitadelLocale) -> String {
        if let s = map[locale.rawValue], !s.isEmpty { return s }
        if let s = map["en"], !s.isEmpty { return s }
        return map.values.first ?? ""
    }
}

enum KeepHelpCategory: String, CaseIterable, Identifiable, Sendable {
    case overview
    case ask
    case agents
    case remote
    case bridges
    case tools
    case sessions
    case assistants
    case teams
    case schedule

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return L10n.t("Overview", "Vue d’ensemble")
        case .ask: return L10n.keepAsk
        case .agents: return L10n.coworkAgents
        case .remote: return L10n.remoteAccess
        case .bridges: return L10n.chatBridges
        case .tools: return L10n.coworkTools
        case .sessions: return L10n.coworkSessions
        case .assistants: return L10n.coworkAssistants
        case .teams: return L10n.coworkTeams
        case .schedule: return L10n.coworkSchedule
        }
    }
}

/// Catalog of Keep help articles. Extend by appending to `all`.
enum KeepHelpCatalog {
    static func articles(forModeRaw mode: String? = nil, query: String = "") -> [KeepHelpArticle] {
        all.filter { article in
            let modeOK = mode == nil || article.modes.isEmpty || article.modes.contains(mode!)
            return modeOK && article.matches(query)
        }
    }

    static func article(id: String) -> KeepHelpArticle? {
        all.first { $0.id == id }
    }

    static let all: [KeepHelpArticle] = [
        KeepHelpArticle(
            id: "keep-what-is",
            category: .overview,
            modes: ["home", "sessions", "assistants", "teams", "tools", "schedule", "agents"],
            title: [
                "en": "What is Keep?",
                "fr": "Qu’est-ce que Keep ?"
            ],
            body: [
                "en": """
Keep is Citadel’s AI workspace. Fortress watches the network; Keep is where you ask agents to read files, write, organize folders, and more — with you in control.

Keep itself is an orchestrator: it talks to models (cloud or on-device) and to external agent CLIs over ACP (Agent Client Protocol). It does not replace Claude Code, Codex, Goose, Hermes, or OpenClaw — those tools run the work when you pick them (or when an assistant is wired to them).

Start on Ask: pick a model, optionally a workspace folder, then send a request. Sessions keep history. Assistants store reusable setups. Plus → Agents is where you see which CLIs are installed on this Mac.
""",
                "fr": """
Keep est l’espace de travail IA de Citadel. Fortress surveille le réseau ; Keep est l’endroit où vous demandez à des agents de lire des fichiers, rédiger, classer des dossiers, etc. — en gardant le contrôle.

Keep est un orchestrateur : il parle aux modèles (cloud ou local) et aux CLI d’agents externes via ACP (Agent Client Protocol). Il ne remplace pas Claude Code, Codex, Goose, Hermes ou OpenClaw — ce sont ces outils qui exécutent le travail lorsque vous les choisissez (ou qu’un assistant y est relié).

Commencez dans Demander : choisissez un modèle, éventuellement un dossier de travail, puis envoyez une requête. Les Sessions conservent l’historique. Les Assistants stockent des configurations réutilisables. Plus → Agents montre quels CLI sont installés sur ce Mac.
"""
            ],
            keywords: ["keep", "overview", "intro", "acp", "orchestrator", "vue", "présentation"]
        ),
        KeepHelpArticle(
            id: "agents-what",
            category: .agents,
            modes: ["agents"],
            title: [
                "en": "Agents page — what is it for?",
                "fr": "Page Agents — à quoi ça sert ?"
            ],
            body: [
                "en": """
The Agents list is a catalog of agent runtimes Keep can talk to. Most rows are third-party CLIs (Claude Code, Codex, Gemini, Goose, Hermes, OpenClaw, Cursor, …).

• Installed — Keep found that CLI on your $PATH (e.g. `claude`, `goose`, `hermes`).
• Not installed — the binary is not on PATH. Install the vendor’s app/CLI, then tap “Scan installed CLIs”.
• Health check — Keep spawns the CLI and runs an ACP handshake. You should see Online / Offline / Missing and an error message if something fails (auth required, command not found, …).
• Connect — add a custom agent by name + command if it is not in the catalog.

Keep does not install these tools for you. Install Claude Code, Goose, Hermes, etc. from their vendors, ensure the binary is on PATH, then scan again.
""",
                "fr": """
La liste Agents est un catalogue de runtimes auxquels Keep peut parler. La plupart des lignes sont des CLI tiers (Claude Code, Codex, Gemini, Goose, Hermes, OpenClaw, Cursor, …).

• Installé — Keep a trouvé ce CLI dans votre $PATH (ex. `claude`, `goose`, `hermes`).
• Non installé — le binaire n’est pas dans le PATH. Installez l’app/CLI du fournisseur, puis « Scanner les CLI installés ».
• Vérifier l’état — Keep lance le CLI et fait un handshake ACP. Vous devez voir En ligne / Hors ligne / Absent et un message d’erreur si ça échoue (auth requise, commande introuvable, …).
• Connecter — ajoutez un agent personnalisé (nom + commande) s’il n’est pas dans le catalogue.

Keep n’installe pas ces outils pour vous. Installez Claude Code, Goose, Hermes, etc. chez leurs éditeurs, assurez-vous que le binaire est dans le PATH, puis rescanner.
"""
            ],
            keywords: ["agents", "cli", "installé", "installed", "path", "scan", "health", "vérifier"]
        ),
        KeepHelpArticle(
            id: "agents-who",
            category: .agents,
            modes: ["agents"],
            title: [
                "en": "Hermes, Goose, OpenClaw & friends",
                "fr": "Hermes, Goose, OpenClaw et les autres"
            ],
            body: [
                "en": """
These names are external coding/agent CLIs. Keep can drive them when they are installed:

• Claude Code / Codex / Gemini / Copilot / Cursor / … — popular vendor CLIs for coding agents.
• Goose — Block’s open agent runtime (CLI on PATH as `goose`).
• Hermes — another ACP-capable agent CLI; install its binary, then scan.
• OpenClaw — agent/runtime in the catalog; needs its CLI present to go Online.
• Keep CLI — Citadel’s bundled/internal agent entry when available.

If a row says Not installed, that product is simply absent from this Mac. That is normal until you install it. Health check cannot succeed until the CLI exists and can authenticate (many need a prior `login` in Terminal).
""",
                "fr": """
Ces noms sont des CLI d’agents externes. Keep peut les piloter une fois installés :

• Claude Code / Codex / Gemini / Copilot / Cursor / … — CLI populaires pour agents de code.
• Goose — runtime agent open source de Block (CLI `goose` dans le PATH).
• Hermes — autre CLI compatible ACP ; installez le binaire, puis scannez.
• OpenClaw — agent/runtime du catalogue ; le CLI doit être présent pour passer En ligne.
• Keep CLI — entrée d’agent interne/bundlée Citadel lorsqu’elle est disponible.

Si une ligne dit Non installé, le produit est simplement absent de ce Mac. C’est normal tant que vous ne l’avez pas installé. Vérifier l’état ne peut réussir que si le CLI existe et peut s’authentifier (beaucoup exigent un `login` préalable dans le Terminal).
"""
            ],
            keywords: ["hermes", "goose", "openclaw", "claude", "codex", "gemini", "cursor"]
        ),
        KeepHelpArticle(
            id: "remote-access",
            category: .remote,
            modes: ["agents"],
            title: [
                "en": "Remote access — how it works",
                "fr": "Accès distant — comment ça marche"
            ],
            body: [
                "en": """
Remote access restarts the Keep backend so it listens on your LAN (0.0.0.0) with HTTP basic auth instead of localhost-only.

1. Toggle Remote access ON (Agents page, below the agent list).
2. Copy the LAN URL, username, and password shown.
3. On another device on the same network, open that URL and sign in.
4. Use the pairing token if the remote UI asks for device pairing.
5. Toggle OFF to return to local-only mode (backend restarts again).

Firewall tip: Fortress’s “Agent firewall” on the same page controls whether the coworkcore process may use the network (allow / ask / deny). It does not replace installing agent CLIs.
""",
                "fr": """
L’accès distant redémarre le backend Keep pour écouter sur le LAN (0.0.0.0) avec authentification HTTP au lieu du seul localhost.

1. Activez Accès distant (page Agents, sous la liste).
2. Copiez l’URL LAN, le nom d’utilisateur et le mot de passe affichés.
3. Sur un autre appareil du même réseau, ouvrez cette URL et connectez-vous.
4. Utilisez le jeton d’appairage si l’UI distante le demande.
5. Désactivez pour revenir en mode local uniquement (le backend redémarre).

Astuce pare-feu : le « Pare-feu de l’agent » sur la même page contrôle si le processus coworkcore peut utiliser le réseau (autoriser / demander / bloquer). Cela ne remplace pas l’installation des CLI.
"""
            ],
            keywords: ["remote", "lan", "password", "distant", "réseau", "qr", "pair"]
        ),
        KeepHelpArticle(
            id: "chat-bridges",
            category: .bridges,
            modes: ["agents"],
            title: [
                "en": "Chat bridges (Telegram, Slack, …)",
                "fr": "Passerelles de chat (Telegram, Slack, …)"
            ],
            body: [
                "en": """
Chat bridges let you talk to Keep agents from messaging apps.

To configure a bridge:
1. Create a bot with the platform (e.g. @BotFather on Telegram) and copy the bot token.
2. On Agents → Chat bridges, paste the token in “Bot token”.
3. Tap Enable. Keep tests the token, then enables the plugin.
4. Approve pending pairings when someone first messages the bot.
5. Disable removes the bridge; Revoke removes an authorized user.

If Enable does nothing, the token field is empty or the test failed — check status messages and that Remote access / network policy allow outbound HTTPS. Platform-specific extras (WeChat QR login, Slack app install) may still require steps outside Citadel.
""",
                "fr": """
Les passerelles de chat permettent de parler aux agents Keep depuis des apps de messagerie.

Pour configurer une passerelle :
1. Créez un bot sur la plateforme (ex. @BotFather sur Telegram) et copiez le jeton.
2. Dans Agents → Passerelles de chat, collez le jeton dans « Jeton du bot ».
3. Appuyez sur Activer. Keep teste le jeton, puis active le plugin.
4. Approuvez les appairages en attente au premier message.
5. Désactiver retire la passerelle ; Révoquer retire un utilisateur autorisé.

Si Activer ne fait rien, le champ jeton est vide ou le test a échoué — regardez les messages d’état et la politique réseau. Certaines plateformes (login QR WeChat, app Slack) peuvent encore demander des étapes hors Citadel.
"""
            ],
            keywords: ["telegram", "slack", "discord", "bot", "token", "jeton", "passerelle", "bridge"]
        ),
        KeepHelpArticle(
            id: "ask-start",
            category: .ask,
            modes: ["home"],
            title: [
                "en": "Ask — first steps",
                "fr": "Demander — premiers pas"
            ],
            body: [
                "en": """
1. Choose a model (cloud API key or on-device MLX / Ollama).
2. Optionally attach a working folder so the agent can read/write there.
3. Set Permissions (Standard asks before risky actions).
4. Type what you need and Send.

If nothing happens, open Providers / Models from the composer and connect a provider. Agent CLIs on the Agents page are optional — many Ask tasks run through Keep’s own model session without Hermes/Goose.
""",
                "fr": """
1. Choisissez un modèle (clé API cloud ou MLX / Ollama local).
2. Joignez éventuellement un dossier de travail pour lecture/écriture.
3. Réglez les Permissions (Standard demande avant les actions risquées).
4. Écrivez votre besoin et Envoyer.

Si rien ne se passe, ouvrez Fournisseurs / Modèles depuis le compositeur. Les CLI de la page Agents sont optionnels — beaucoup de tâches Demander passent par la session modèle de Keep sans Hermes/Goose.
"""
            ],
            keywords: ["ask", "demander", "model", "modèle", "workspace", "dossier"]
        ),
        KeepHelpArticle(
            id: "sessions",
            category: .sessions,
            modes: ["sessions"],
            title: [
                "en": "Sessions",
                "fr": "Sessions"
            ],
            body: [
                "en": "Sessions are past and current chats with Keep. Open one to continue, rename, fork, or reset. Empty list means you have not sent a request from Ask yet.",
                "fr": "Les Sessions sont vos conversations Keep. Ouvrez-en une pour continuer, renommer, dupliquer ou réinitialiser. Une liste vide signifie qu’aucune requête n’a encore été envoyée depuis Demander."
            ],
            keywords: ["sessions", "history", "historique"]
        ),
        KeepHelpArticle(
            id: "assistants",
            category: .assistants,
            modes: ["assistants"],
            title: [
                "en": "Assistants",
                "fr": "Assistants"
            ],
            body: [
                "en": "Assistants are reusable agent profiles (name, model preferences, skills). Create one to avoid reconfiguring Ask every time. They sit above the raw CLI catalog on Agents.",
                "fr": "Les Assistants sont des profils d’agent réutilisables (nom, modèle, compétences). Créez-en un pour éviter de reconfigurer Demander à chaque fois. Ils se placent au-dessus du catalogue CLI de la page Agents."
            ],
            keywords: ["assistants", "profil", "profile"]
        ),
        KeepHelpArticle(
            id: "tools-mcp",
            category: .tools,
            modes: ["tools"],
            title: [
                "en": "Tools (MCP)",
                "fr": "Outils (MCP)"
            ],
            body: [
                "en": "MCP tools extend what agents can call (APIs, browsers, custom servers). Add a server URL or local command, then enable it for sessions. OAuth servers may need Login from this page.",
                "fr": "Les outils MCP étendent ce que les agents peuvent appeler (APIs, navigateurs, serveurs custom). Ajoutez une URL ou une commande locale, puis activez-les pour les sessions. Les serveurs OAuth peuvent exiger une Connexion depuis cette page."
            ],
            keywords: ["mcp", "tools", "outils", "oauth"]
        ),
        KeepHelpArticle(
            id: "agents-cli-auth",
            category: .agents,
            modes: ["agents", "teams"],
            title: [
                "en": "CLI authentication — why Terminal first?",
                "fr": "Authentification CLI — pourquoi le Terminal d’abord ?"
            ],
            body: [
                "en": """
Keep discovers agent CLIs on your Mac’s PATH, but many vendors require a one-time sign-in in Terminal before third-party apps can use them.

Typical flow:
1. Install the CLI (Claude Code, Codex, Cursor agent, Hermes, Goose, …).
2. Open Terminal and run the command once — e.g. `claude`, `codex`, or the vendor’s `login` subcommand.
3. Complete the browser or API-key prompt in Terminal.
4. Back in Keep → Agents, tap “Scan installed CLIs”, then “Health check”.

Keep only verifies that the CLI responds to ACP — it does not perform vendor login for you. If Health check stays Offline after install, Terminal auth is the most common fix.

Claude Code note: Claude Pro/Max subscription may not apply when driving Claude through third-party apps. You may need an Anthropic API key configured in Terminal instead of relying on subscription-only auth.
""",
                "fr": """
Keep détecte les CLI d’agents dans le PATH de votre Mac, mais beaucoup de fournisseurs exigent une connexion unique dans le Terminal avant qu’une app tierce puisse les utiliser.

Flux typique :
1. Installez le CLI (Claude Code, Codex, agent Cursor, Hermes, Goose, …).
2. Ouvrez le Terminal et lancez la commande une fois — ex. `claude`, `codex`, ou la sous-commande `login` du fournisseur.
3. Terminez l’invite navigateur ou clé API dans le Terminal.
4. Dans Keep → Agents, « Scanner les CLI installés », puis « Vérifier l’état ».

Keep vérifie seulement que le CLI répond à ACP — il ne fait pas la connexion à votre place. Si Vérifier l’état reste Hors ligne après installation, l’auth Terminal est la cause la plus fréquente.

Note Claude Code : l’abonnement Claude Pro/Max peut ne pas s’appliquer via des apps tierces. Une clé API Anthropic configurée dans le Terminal peut être nécessaire plutôt que l’auth par abonnement seul.
"""
            ],
            keywords: ["auth", "login", "terminal", "codex", "claude", "offline", "health", "authentification"]
        ),
        KeepHelpArticle(
            id: "teams",
            category: .teams,
            modes: ["teams"],
            title: [
                "en": "Teams",
                "fr": "Équipes"
            ],
            body: [
                "en": """
Teams orchestrate several agents on a shared workspace: pick a leader and members, then describe a task.

Setup checklist:
• Leader — usually Citadel Keep (built-in). Uses your cloud or local model from Ask.
• Members — often external CLIs (Claude Code, Codex, Cursor, Hermes…). Each must be Installed and Online on the Agents page before joining a team.
• Terminal auth — run each CLI once in Terminal and sign in, then Health check in Keep.
• Workspace folder — optional shared directory for file tasks.

If creating a team with multiple CLIs fails, try: (1) Health check each CLI on Agents, (2) create a Keep-only team first, (3) add members one at a time after each shows Online.

Teams pick assistants, not raw Agents rows — generated assistants appear after a successful scan and health check.
""",
                "fr": """
Les Équipes orchestrent plusieurs agents sur un espace partagé : choisissez un leader et des membres, puis décrivez une tâche.

Checklist :
• Leader — en général Citadel Keep (intégré). Utilise votre modèle cloud ou local de Demander.
• Membres — souvent des CLI externes (Claude Code, Codex, Cursor, Hermes…). Chacun doit être Installé et En ligne sur la page Agents avant de rejoindre l’équipe.
• Auth Terminal — lancez chaque CLI une fois dans le Terminal et connectez-vous, puis Vérifier l’état dans Keep.
• Dossier de travail — répertoire partagé optionnel pour les fichiers.

Si la création avec plusieurs CLI échoue : (1) Vérifier l’état de chaque CLI sur Agents, (2) créer d’abord une équipe Keep seule, (3) ajouter les membres un par un une fois En ligne.

Les Équipes choisissent des Assistants, pas les lignes brutes Agents — les assistants générés apparaissent après un scan et une vérification réussis.
"""
            ],
            keywords: ["teams", "équipes", "leader", "cli", "members", "membres"]
        ),
        KeepHelpArticle(
            id: "schedule",
            category: .schedule,
            modes: ["schedule"],
            title: [
                "en": "Schedule",
                "fr": "Planification"
            ],
            body: [
                "en": "Scheduled tasks run Keep prompts on a cron-like cadence. Create a task with a prompt, schedule, and optional workspace. Requires the Keep backend to be running when the trigger fires.",
                "fr": "Les tâches planifiées exécutent des prompts Keep selon une cadence type cron. Créez une tâche avec prompt, planning et dossier optionnel. Le backend Keep doit tourner au moment du déclenchement."
            ],
            keywords: ["schedule", "cron", "planification", "tâche"]
        ),
        KeepHelpArticle(
            id: "agent-firewall",
            category: .remote,
            modes: ["agents"],
            title: [
                "en": "Agent firewall",
                "fr": "Pare-feu de l’agent"
            ],
            body: [
                "en": "This Fortress rule applies to the Keep backend process (coworkcore), not to every CLI like Hermes individually. Choose No rule, Always allow, Ask every time, or Block for that process’s network access.",
                "fr": "Cette règle Fortress s’applique au processus backend Keep (coworkcore), pas à chaque CLI comme Hermes individuellement. Choisissez Aucune règle, Toujours autoriser, Demander à chaque fois, ou Bloquer."
            ],
            keywords: ["firewall", "pare-feu", "fortress", "coworkcore"]
        )
    ]
}

/// Short blurbs for known agent backends (when the API sends no description).
enum KeepAgentBlurb {
    static func text(for agent: CoworkManagedAgent) -> String {
        if let d = agent.description, !d.isEmpty { return d }
        let key = (agent.backend ?? agent.id).lowercased()
        switch key {
        case "claude", "claude-code":
            return L10n.t("Anthropic’s Claude Code CLI (ACP).", "CLI Claude Code d’Anthropic (ACP).")
        case "codex":
            return L10n.t("OpenAI Codex CLI agent.", "Agent CLI Codex (OpenAI).")
        case "gemini":
            return L10n.t("Google Gemini CLI agent.", "Agent CLI Gemini (Google).")
        case "goose":
            return L10n.t("Block’s Goose open agent runtime.", "Runtime agent open Goose (Block).")
        case "hermes":
            return L10n.t("Hermes ACP agent CLI — install the binary, then scan.", "CLI agent ACP Hermes — installez le binaire, puis scannez.")
        case "openclaw":
            return L10n.t("OpenClaw agent runtime (CLI must be on PATH).", "Runtime agent OpenClaw (CLI dans le PATH).")
        case "cursor":
            return L10n.t("Cursor agent CLI bridge.", "Pont CLI agent Cursor.")
        case "copilot":
            return L10n.t("GitHub Copilot CLI agent.", "Agent CLI GitHub Copilot.")
        case "opencode", "qwen", "kimi", "kiro", "droid", "auggie", "qoder", "vibe", "snow", "codebuddy":
            return L10n.t("Third-party ACP-compatible agent CLI.", "CLI agent tiers compatible ACP.")
        case "nanobot":
            return L10n.t("Legacy nanobot entry (often deprecated).", "Entrée nanobot héritée (souvent dépréciée).")
        default:
            if agent.id.lowercased().contains("keep") || key.contains("aion") {
                return L10n.t("Keep’s bundled / internal agent entry.", "Entrée d’agent interne / bundlée Keep.")
            }
            return L10n.t("External agent CLI Keep can drive when installed.", "CLI agent externe que Keep peut piloter une fois installé.")
        }
    }
}
