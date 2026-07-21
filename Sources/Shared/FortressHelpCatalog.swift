import Foundation

struct FortressHelpArticle: Identifiable, Hashable, Sendable {
    let id: String
    let category: FortressHelpCategory
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

enum FortressHelpCategory: String, CaseIterable, Identifiable, Sendable {
    case overview
    case activity
    case suspects
    case history
    case rules
    case protection
    case dns
    case keep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return L10n.t("Overview", "Vue d’ensemble")
        case .activity: return L10n.fortressActivity
        case .suspects: return L10n.fortressSuspects
        case .history: return L10n.fortressHistory
        case .rules: return L10n.fortressRules
        case .protection: return L10n.protectionStatus
        case .dns: return L10n.settingsDNS
        case .keep: return L10n.keep
        }
    }
}

enum FortressHelpCatalog {
    static func articles(forModeRaw mode: String? = nil, query: String = "") -> [FortressHelpArticle] {
        all.filter { article in
            let modeOK = mode == nil || article.modes.isEmpty || article.modes.contains(mode!)
            return modeOK && article.matches(query)
        }
    }

    static func article(id: String) -> FortressHelpArticle? {
        all.first { $0.id == id }
    }

    static let all: [FortressHelpArticle] = [
        FortressHelpArticle(
            id: "fortress-what-is",
            category: .overview,
            modes: ["activity", "suspects", "history", "rules", "settings"],
            title: [
                "en": "What is Fortress?",
                "fr": "Qu’est-ce que Fortress ?"
            ],
            body: [
                "en": """
Fortress is Citadel’s network guardian. It shows which apps talk to the internet, where traffic goes on a map, and lets you allow or block connections.

Keep (your AI agents) is guarded by Fortress: agent traffic can follow the same rules as other apps.
""",
                "fr": """
Fortress est le gardien réseau de Citadel. Il montre quelles apps parlent à Internet, où va le trafic sur une carte, et vous laisse autoriser ou bloquer.

Keep (vos agents IA) est gardé par Fortress : le trafic des agents peut suivre les mêmes règles que les autres apps.
"""
            ],
            keywords: ["firewall", "pare-feu", "network", "réseau", "citadel"]
        ),
        FortressHelpArticle(
            id: "fortress-protection",
            category: .protection,
            modes: ["settings", "activity"],
            title: [
                "en": "Protection active — what it means",
                "fr": "Protection active — ce que ça veut dire"
            ],
            body: [
                "en": """
Full protection uses Citadel’s per-app network filter (a macOS system extension). The first time, macOS asks you to approve Citadel in System Settings → Privacy & Security.

Until approval, Fortress can still show Activity in local mode, but blocking an app may be limited.

Also approve the privileged helper under Login Items so DNS filtering and advanced rules work.
""",
                "fr": """
La protection complète utilise le filtre réseau par app de Citadel (extension système macOS). La première fois, macOS vous demande d’approuver Citadel dans Réglages Système → Confidentialité et sécurité.

Avant l’approbation, Fortress peut encore montrer l’Activité en mode local, mais bloquer une app peut être limité.

Approuvez aussi l’assistant privilégié dans Éléments d’ouverture pour le filtrage DNS et les règles avancées.
"""
            ],
            keywords: ["approval", "approbation", "extension", "filter", "filtre", "protection"]
        ),
        FortressHelpArticle(
            id: "fortress-alerts",
            category: .rules,
            modes: ["activity", "rules", "settings"],
            title: [
                "en": "Connection alerts",
                "fr": "Alertes de connexion"
            ],
            body: [
                "en": """
When Fortress is in Ask mode, unknown connections can pause and ask you.

Choose:
• Any connection from this app
• This website / host only
• This IP and port only

And how long to remember: forever, until quit, 1 hour, or 24 hours.

You’ll also see if the app is signed.
""",
                "fr": """
En mode Demander, les connexions inconnues peuvent se mettre en pause et vous demander.

Choisissez :
• Toute connexion de cette app
• Ce site / hôte seulement
• Cette IP et ce port seulement

Et la durée : pour toujours, jusqu’à la fermeture, 1 heure ou 24 heures.

Vous voyez aussi si l’app est signée.
"""
            ],
            keywords: ["alert", "alerte", "allow", "deny", "autoriser", "refuser"]
        ),
        FortressHelpArticle(
            id: "fortress-suspects",
            category: .suspects,
            modes: ["suspects", "activity"],
            title: [
                "en": "Suspicious communications",
                "fr": "Communications suspectes"
            ],
            body: [
                "en": """
The Suspects tab lists connections with hard, checkable reasons — not vague “AI risk scores”.

Examples:
• App is not code-signed
• First time this app or destination appears
• Sensitive port for a consumer app
• Background helper contacting a new server
• Destination on an enabled DNS blocklist

Tap “Why is this listed?” then Allow, Deny, or open it in Activity.
""",
                "fr": """
L’onglet Suspects liste des connexions avec des raisons dures et vérifiables — pas un score « IA » flou.

Exemples :
• App non signée
• Première fois pour cette app ou destination
• Port sensible pour une app grand public
• Helper d’arrière-plan vers un nouveau serveur
• Destination sur une blocklist DNS active

Appuyez sur « Pourquoi c’est listé ? » puis Autoriser, Refuser, ou ouvrir dans Activité.
"""
            ],
            keywords: ["suspect", "unsigned", "non signé", "threat", "risque"]
        ),
        FortressHelpArticle(
            id: "fortress-history",
            category: .history,
            modes: ["history"],
            title: [
                "en": "Connection history",
                "fr": "Historique des connexions"
            ],
            body: [
                "en": """
History keeps recent connections on this Mac (about 7 days by default). Filter by app or host, and export CSV if you need a record.
""",
                "fr": """
L’historique conserve les connexions récentes sur ce Mac (environ 7 jours par défaut). Filtrez par app ou hôte, et exportez en CSV si besoin.
"""
            ],
            keywords: ["history", "historique", "csv", "export"]
        ),
        FortressHelpArticle(
            id: "fortress-rules",
            category: .rules,
            modes: ["rules"],
            title: [
                "en": "Rules",
                "fr": "Règles"
            ],
            body: [
                "en": """
Rules remember allow/deny decisions. Prefer rules tied to a signed Team ID + app when possible — more reliable than the process name alone.

Temporary rules expire automatically. “Until quit” rules are cleared when you quit Citadel.
""",
                "fr": """
Les règles mémorisent autoriser/refuser. Préférez les règles liées à un Team ID signé + app quand c’est possible — plus fiable que le seul nom du processus.

Les règles temporaires expirent automatiquement. « Jusqu’à la fermeture » est effacé quand vous quittez Citadel.
"""
            ],
            keywords: ["rule", "règle", "team id", "temporary", "temporaire"]
        ),
        FortressHelpArticle(
            id: "fortress-dns",
            category: .dns,
            modes: ["settings"],
            title: [
                "en": "DNS and blocklists",
                "fr": "DNS et blocklists"
            ],
            body: [
                "en": """
Citadel can filter domain names before apps connect (ads, trackers, known-bad hosts). Turn on “Use system DNS via Citadel” and enable the lists you want under Blocklists.
""",
                "fr": """
Citadel peut filtrer les noms de domaine avant que les apps se connectent (pubs, trackers, hôtes connus). Activez « Utiliser le DNS système via Citadel » et les listes voulues sous Blocklists.
"""
            ],
            keywords: ["dns", "blocklist", "ads", "pubs", "tracker"]
        ),
        FortressHelpArticle(
            id: "fortress-keep",
            category: .keep,
            modes: ["activity", "settings"],
            title: [
                "en": "Keep is guarded by Fortress",
                "fr": "Keep est gardé par Fortress"
            ],
            body: [
                "en": """
Keep is Citadel’s agent workspace (local models or your cloud keys). It is not a separate product bolted on — Fortress can watch and constrain agent network traffic like any other process.

Open Keep from the main Citadel navigation when you want agents to help with files, code, or chores.
""",
                "fr": """
Keep est l’espace agents de Citadel (modèles locaux ou vos clés cloud). Ce n’est pas un produit séparé greffé — Fortress peut surveiller et contraindre le trafic réseau des agents comme n’importe quel processus.

Ouvrez Keep depuis la navigation Citadel pour les fichiers, le code ou les tâches.
"""
            ],
            keywords: ["keep", "agent", "ai", "ia"]
        ),
        FortressHelpArticle(
            id: "fortress-activity",
            category: .activity,
            modes: ["activity"],
            title: [
                "en": "Activity view",
                "fr": "Vue Activité"
            ],
            body: [
                "en": """
Activity groups traffic by app family, then helpers, then sites. The map shows where connections go. Select a stream to allow/deny for 1 hour or permanently.
""",
                "fr": """
Activité regroupe le trafic par famille d’app, puis helpers, puis sites. La carte montre où vont les connexions. Sélectionnez un flux pour autoriser/refuser 1 heure ou pour de bon.
"""
            ],
            keywords: ["activity", "activité", "map", "carte", "family", "famille"]
        ),
    ]
}
