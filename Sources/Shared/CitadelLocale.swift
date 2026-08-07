import Foundation
import SwiftUI

/// Citadel localization — English + French.
enum CitadelLocale: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        }
    }

    static var current: CitadelLocale {
        let raw = UserDefaults.standard.string(forKey: "citadel.locale")
            ?? Locale.preferredLanguages.first?.prefix(2).lowercased()
            ?? "en"
        return CitadelLocale(rawValue: String(raw)) ?? .english
    }

    static func setCurrent(_ locale: CitadelLocale) {
        let key = "citadel.locale"
        if UserDefaults.standard.string(forKey: key) != locale.rawValue {
            UserDefaults.standard.set(locale.rawValue, forKey: key)
        }
        NotificationCenter.default.post(name: .citadelLocaleDidChange, object: locale)
    }
}

extension Notification.Name {
    static let citadelLocaleDidChange = Notification.Name("citadel.locale.didChange")
}

enum L10n {
    private static var fr: Bool { CitadelLocale.current == .french }

    static func t(_ en: String, _ french: String) -> String {
        fr ? french : en
    }

    // MARK: - Shell

    /// Product name for the AI workspace (inner stronghold). Internal code may still say Cowork.
    static var keep: String { t("Keep", "Keep") }
    static var keepBrand: String { t("Citadel Keep", "Citadel Keep") }
    static var openKeep: String { t("Open Keep…", "Ouvrir Keep…") }
    static var keepAsk: String { t("Ask", "Demander") }
    static var keepMore: String { t("More", "Plus") }
    static var keepSubtitleAsk: String {
        t("Keep · Your agents inside the walls", "Keep · Vos agents à l’intérieur des murs")
    }
    static var keepWelcomeTitle: String {
        t("This is the Keep", "Voici le Keep")
    }
    static var keepWelcomeBody: String {
        t(
            "Fortress watches the network. The Keep is where local AI agents help with files, code, and chores — privately on your Mac.",
            "Fortress surveille le réseau. Le Keep est l’endroit où des agents IA locaux aident pour fichiers, code et tâches — en privé sur votre Mac."
        )
    }
    static var keepStep1: String { t("1. Connect a model", "1. Connectez un modèle") }
    static var keepStep2: String { t("2. Type what you need", "2. Écrivez ce dont vous avez besoin") }
    static var keepStep3: String { t("3. Review before anything risky runs", "3. Validez avant toute action risquée") }
    static var keepReadyHint: String {
        t("Try: “Summarize the PDF on my Desktop” or “Organize Downloads by type”.",
          "Essayez : « Résume le PDF sur mon Bureau » ou « Classe Téléchargements par type ».")
    }

    static var coworkHome: String { keepAsk }
    static var coworkSessions: String { t("Sessions", "Sessions") }
    static var coworkAssistants: String { t("Assistants", "Assistants") }
    static var coworkTools: String { t("Tools", "Outils") }
    static var coworkSchedule: String { t("Schedule", "Planification") }
    static var coworkAgents: String { t("Agents", "Agents") }
    static var monitor: String { t("Monitor", "Surveillance") }
    static var language: String { t("Language", "Langue") }

    // MARK: - Session

    static var agentWorking: String { t("Agent working…", "Agent en cours…") }
    static var stop: String { t("Stop", "Arrêter") }
    static var back: String { t("Back", "Retour") }
    static var resetSession: String { t("Reset session", "Réinitialiser la session") }
    static var forkSession: String { t("Fork session", "Dupliquer la session") }
    static var searchMessages: String { t("Search messages…", "Rechercher dans les messages…") }
    static var tokens: String { t("tokens", "jetons") }
    static var session: String { t("Session", "Session") }
    static var sessionName: String { t("Session name", "Nom de la session") }
    static var renameSessionHelp: String { t("Double-click to rename", "Double-cliquer pour renommer") }
    static var loadEarlierMessages: String { t("Load earlier messages", "Charger les messages précédents") }
    static var send: String { t("Send", "Envoyer") }
    static var sendHelp: String { t("Send reply (Return)", "Envoyer (Entrée)") }
    static var attach: String { t("Attach", "Joindre") }
    static var attachHelp: String {
        t("Attach PDFs, Word, images — indexed into the workspace and sent to the agent",
          "Joindre PDF, Word, images — indexés dans l'espace de travail et envoyés à l'agent")
    }
    static var replyPlaceholder: String { t("Reply to Keep…", "Répondre à Keep…") }
    static var messagePlaceholder: String { t("Ask Keep…", "Demander à Keep…") }
    static var message: String { t("Message", "Message") }

    // MARK: - Reasoning

    static var reasoning: String { t("Reasoning", "Raisonnement") }
    static var reasoningActive: String { t("Reasoning…", "Raisonnement…") }

    // MARK: - Voice

    static var voiceScribe: String { t("Voice Scribe", "Dictée vocale") }
    static var voiceListening: String { t("Listening…", "Écoute…") }
    static var voiceTapToSpeak: String { t("Tap to dictate", "Appuyer pour dicter") }
    static var voicePermissionDenied: String {
        t("Voice Scribe needs microphone and speech recognition access.",
          "La dictée vocale nécessite l'accès au micro et à la reconnaissance vocale.")
    }

    // MARK: - Desk companion

    static var deskCompanion: String { t("Desk Companion", "Compagnon de bureau") }
    static var companionEnabled: String { t("Show Desk Companion", "Afficher le compagnon") }
    static var companionDnd: String { t("Quiet mode", "Mode silencieux") }

    // MARK: - Cron

    static var scheduledTasks: String { t("Scheduled tasks", "Tâches planifiées") }
    static var newScheduledTask: String { t("New task", "Nouvelle tâche") }
    static var runNow: String { t("Run now", "Exécuter") }
    static var cronEnabled: String { t("Enabled", "Activé") }
    static var cronDisabled: String { t("Disabled", "Désactivé") }
    static var cronSchedule: String { t("Schedule", "Planification") }
    static var cronPrompt: String { t("Prompt", "Consigne") }
    static var cronSave: String { t("Save", "Enregistrer") }
    static var cronCancel: String { t("Cancel", "Annuler") }
    static var cronDelete: String { t("Delete", "Supprimer") }
    static var cronNoTasks: String { t("No scheduled tasks yet.", "Aucune tâche planifiée.") }
    static var cronEmpty: String {
        t("No scheduled tasks yet. Automate recurring Keep prompts here.",
          "Aucune tâche planifiée. Automatisez ici des consignes Keep récurrentes.")
    }
    static var editScheduledTask: String { t("Edit task", "Modifier la tâche") }
    static var cronName: String { t("Name", "Nom") }
    static var cronExpression: String { t("Cron expression", "Expression cron") }
    static var cronPresets: String { t("Presets", "Préréglages") }
    static var cronPresetEvery15: String { t("Every 15 minutes", "Toutes les 15 minutes") }
    static var cronPresetHourly: String { t("Every hour", "Toutes les heures") }
    static var cronPresetDaily9: String { t("Daily at 9:00", "Chaque jour à 9h00") }
    static var cronPresetWeekdays9: String { t("Weekdays at 9:00", "En semaine à 9h00") }
    static var cronPresetMonday9: String { t("Mondays at 9:00", "Le lundi à 9h00") }

    // MARK: - Confirmations

    static var permissionRequired: String { t("Permission required", "Autorisation requise") }
    static var alwaysAllow: String { t("Always allow", "Toujours autoriser") }
    static func pendingConfirmations(_ count: Int) -> String {
        t("\(count) pending confirmation\(count > 1 ? "s" : "")",
          "\(count) confirmation\(count > 1 ? "s" : "") en attente")
    }
    static func confirmationQueuePosition(_ index: Int, _ total: Int) -> String {
        t("\(index) of \(total)", "\(index) sur \(total)")
    }

    // MARK: - MCP OAuth

    static var oauthConnected: String { t("Connected", "Connecté") }
    static var oauthLogin: String { t("Sign in", "Se connecter") }
    static var oauthLogout: String { t("Sign out", "Se déconnecter") }
    static var oauthLoginFailed: String { t("OAuth login failed", "Échec de la connexion OAuth") }
    static var agentSessionFolder: String { t("Agent session folder", "Dossier de session de l'agent") }

    // MARK: - Skills hub / editors

    static var assistantLabel: String { t("Assistant", "Assistant") }
    static var assistantRuleLabel: String { t("Assistant rule (markdown)", "Règle de l'assistant (markdown)") }
    static var reload: String { t("Reload", "Recharger") }
    static var saved: String { t("Saved", "Enregistré") }
    static var saveRule: String { t("Save rule", "Enregistrer la règle") }
    static var saveRuleKeepsOpen: String {
        t("Saves the rule without closing this window.",
          "Enregistre la règle sans fermer la fenêtre.")
    }
    static var availableSkills: String { t("Available skills", "Compétences disponibles") }
    static var loading: String { t("Loading…", "Chargement…") }
    static var assistantEditor: String { t("Assistant editor", "Éditeur d'assistant") }
    static var newAssistant: String { t("New assistant", "Nouvel assistant") }
    static var editFile: String { t("Edit file", "Modifier le fichier") }
    static var stageAll: String { t("Accept all", "Tout accepter") }
    static var voiceTranscribing: String { t("Transcribing…", "Transcription…") }

    // MARK: - Misc views i18n

    static var refreshModels: String { t("Refresh models", "Actualiser les modèles") }
    static var mlxManagerSubtitle: String {
        t("Download MLX models to run on-device with native Apple Silicon inference.",
          "Téléchargez des modèles MLX pour une inférence native sur Apple Silicon.")
    }
    static var searchModels: String { t("Search models…", "Rechercher des modèles…") }
    static func mlxRemoveConfirm(_ id: String) -> String {
        t("Remove downloaded weights for \(id)?", "Supprimer les poids téléchargés de \(id) ?")
    }
    static var mlxMoreRAM: String {
        t("More RAM recommended for this model", "Plus de RAM recommandée pour ce modèle")
    }
    static var mlxFirstTimeSetup: String { t("First-time MLX setup", "Première installation MLX") }
    static var mlxDeleteLocalTitle: String { t("Delete local model?", "Supprimer le modèle local ?") }
    static var download: String { t("Download", "Télécharger") }
    static var resumeDownload: String { t("Resume", "Reprendre") }
    static var mlxSetupHelp: String {
        t("Citadel installs the on-device runtime automatically when you pick a model — no Terminal commands.",
          "Citadel installe automatiquement le runtime local quand vous choisissez un modèle — aucune commande Terminal.")
    }
    static var agentsSubtitle: String {
        t("Keep orchestrates external agent CLIs (Claude Code, Goose, Hermes…). Installed means the binary is on this Mac’s PATH — Keep does not install them for you.",
          "Keep orchestre des CLI d’agents externes (Claude Code, Goose, Hermes…). Installé signifie que le binaire est dans le PATH de ce Mac — Keep ne les installe pas pour vous.")
    }
    static var agentsEmptyHint: String {
        t("No agents in the catalog yet. Wait for the backend, then Scan installed CLIs.",
          "Aucun agent dans le catalogue. Attendez le backend, puis Scanner les CLI installés.")
    }
    static var connectAgentHint: String {
        t("Point Keep at a custom ACP-compatible command (name + executable).",
          "Indiquez à Keep une commande ACP personnalisée (nom + exécutable).")
    }
    static var agentEnabledHelp: String {
        t("Include this agent in Keep’s catalog when enabled.",
          "Inclure cet agent dans le catalogue Keep lorsqu’il est activé.")
    }
    static var agentStatusOnline: String { t("Online", "En ligne") }
    static var agentStatusOffline: String { t("Offline", "Hors ligne") }
    static var agentStatusMissing: String { t("Missing", "Absent") }
    static var agentMissingCLI: String {
        t("CLI not found on PATH", "CLI introuvable dans le PATH")
    }
    static var agentUnchecked: String {
        t("Not checked yet — tap Health check", "Pas encore vérifié — appuyez sur Vérifier l’état")
    }
    static var keepHelpTitle: String { t("Keep guide", "Guide Keep") }
    static var keepHelpShort: String { t("Guide", "Guide") }
    static var keepHelpSearch: String { t("Search help…", "Rechercher dans l’aide…") }
    static var keepHelpPick: String { t("Choose a topic on the left.", "Choisissez un sujet à gauche.") }
    static var keepHelpNoResults: String { t("No matching articles.", "Aucun article correspondant.") }
    static func keepHelpForPage(_ page: String) -> String {
        t("Suggested for \(page)", "Suggéré pour \(page)")
    }
    static var command: String { t("Command", "Commande") }
    static var connect: String { t("Connect", "Connecter") }
    static var renameSession: String { t("Rename session", "Renommer la session") }
    static var renameEllipsis: String { t("Rename…", "Renommer…") }
    static var thinkingLabel: String { t("Thinking", "Réflexion") }
    static var assistantResponding: String { t("Assistant is responding", "L'assistant répond") }
    static var providersSubtitle: String {
        t("Connect cloud APIs or local runtimes (Ollama, LM Studio).",
          "Connectez des API cloud ou des runtimes locaux (Ollama, LM Studio).")
    }
    static var noSessionsTitle: String { t("No sessions yet", "Aucune session") }
    static var noSessionsSubtitle: String {
        t("Go to Ask, connect a model if needed, then send your first request.",
          "Allez dans Demander, connectez un modèle si besoin, puis envoyez votre première demande.")
    }
    static var untitled: String { t("Untitled", "Sans titre") }
    static var providerLabel: String { t("Provider", "Fournisseur") }
    static var baseURLLabel: String { t("Base URL", "URL de base") }
    static var apiKeyLabel: String { t("API key", "Clé API") }
    static var loadModels: String { t("Load models", "Charger les modèles") }
    static var discovering: String { t("Discovering…", "Découverte…") }
    static var savingEllipsis: String { t("Saving…", "Enregistrement…") }
    static var modelLabel: String { t("Model", "Modèle") }
    static var pdfLoadFailed: String { t("Unable to load PDF.", "Impossible de charger le PDF.") }

    // MARK: - Workspace

    static var workspace: String { t("Workspace", "Espace de travail") }
    static var searchFiles: String { t("Search files…", "Rechercher des fichiers…") }
    static var changes: String { t("Changes", "Modifications") }
    static var stageChange: String { t("Stage", "Indexer") }
    static var discardChanges: String { t("Discard", "Annuler") }
    static var resetSnapshot: String { t("Reset snapshot", "Réinitialiser l'instantané") }
    static var files: String { t("Files", "Fichiers") }
    static var up: String { t("Up", "Monter") }
    static var rename: String { t("Rename", "Renommer") }
    static var delete: String { t("Delete", "Supprimer") }
    static var reveal: String { t("Reveal", "Afficher") }
    static var previewDiff: String { t("Preview diff", "Aperçu des différences") }
    static var renameFile: String { t("Rename file", "Renommer le fichier") }
    static var workspaceFolder: String { t("Workspace folder", "Dossier de travail") }
    static var removeWorkspace: String { t("Remove", "Retirer") }
    static var removeWorkspaceHelp: String {
        t("Stop using this folder for the next chat",
          "Ne plus utiliser ce dossier pour le prochain chat")
    }
    static var workspaceHelp: String {
        t("Your folder when set on Ask; otherwise Keep’s per-session sandbox.",
          "Votre dossier si défini sur Demander ; sinon le bac à sable Keep.")
    }
    static var workspaceEmpty: String {
        t("No files yet. Attach PDFs or documents with Joindre — they are indexed here when you send. Or pick a folder on Home for the agent to work in.",
          "Aucun fichier. Joignez un PDF ou un document avec Joindre — il sera indexé ici à l'envoi. Ou choisissez un dossier sur l'accueil.")
    }

    // MARK: - Preview

    static var preview: String { t("Preview", "Aperçu") }
    static var previewEmpty: String {
        t("Click an attached file chip or a workspace file on the left to preview it here. The agent's output also appears here.",
          "Cliquez sur une pièce jointe ou un fichier de l'espace de travail (à gauche) pour l'afficher ici. La sortie de l'agent apparaît aussi ici.")
    }
    static var previewAttachment: String {
        t("Click to preview in the Preview panel", "Cliquer pour afficher dans Aperçu")
    }
    static func attachmentsCopyPartial(_ detail: String) -> String {
        t("Some attachments could not be copied: \(detail)", "Certaines pièces jointes n'ont pas pu être copiées : \(detail)")
    }
    static var documentContextHeader: String {
        t("Document excerpts attached for this message:", "Extraits de documents joints pour ce message :")
    }
    static var attachmentIndexed: String {
        t("Indexed — text will be sent to the model", "Indexé — le texte sera envoyé au modèle")
    }
    static var documentIndexed: String {
        t("Indexed document", "Document indexé")
    }
    static var documentIndexing: String {
        t("Indexing…", "Indexation…")
    }
    static var openInApp: String { t("Open in default app", "Ouvrir dans l'app par défaut") }
    static var quickLook: String { t("Quick Look", "Coup d'œil") }
    static var scanAgents: String { t("Scan installed CLIs", "Scanner les CLI installés") }
    static var scanningAgents: String { t("Scanning…", "Scan en cours…") }
    static func agentsDetected(_ n: Int) -> String {
        t("\(n) agent\(n == 1 ? "" : "s") detected on this Mac", "\(n) agent\(n == 1 ? "" : "s") détecté\(n == 1 ? "" : "s") sur ce Mac")
    }
    static var installedBadge: String { t("Installed", "Installé") }
    static var notInstalledBadge: String { t("Not installed", "Non installé") }
    static var testConnection: String { t("Test connection", "Tester la connexion") }

    static var browse: String { t("Browse…", "Parcourir…") }

    // MARK: - Teams
    static var coworkTeams: String { t("Teams", "Équipes") }
    static var teamsEmpty: String {
        t("No teams yet. Create one to orchestrate several agents on a shared workspace.",
          "Aucune équipe. Créez-en une pour orchestrer plusieurs agents sur un espace de travail partagé.")
    }
    static var newTeam: String { t("New team", "Nouvelle équipe") }
    static var teamName: String { t("Team name", "Nom de l'équipe") }
    static var teamLeader: String { t("Leader", "Leader") }
    static var teamMember: String { t("Member", "Membre") }
    static var teamMembers: String { t("Members", "Membres") }
    static var addMember: String { t("Add member", "Ajouter un membre") }
    static var removeMember: String { t("Remove member", "Retirer le membre") }
    static var createTeam: String { t("Create team", "Créer l'équipe") }
    static var teamTaskPlaceholder: String {
        t("Describe the task — the leader will delegate to the team…",
          "Décrivez la tâche — le leader la répartira dans l'équipe…")
    }
    static var teamRunning: String { t("Team run in progress", "Exécution d'équipe en cours") }
    static var teamIdle: String { t("Team idle", "Équipe au repos") }
    static var cancelRun: String { t("Cancel run", "Annuler l'exécution") }
    static var pauseAgent: String { t("Pause", "Pause") }
    static var cancelAgent: String { t("Cancel", "Annuler") }
    static var openTeam: String { t("Open", "Ouvrir") }
    static var deleteTeam: String { t("Delete team", "Supprimer l'équipe") }
    static var renameTeam: String { t("Rename team", "Renommer l'équipe") }
    static var teamNoMessages: String { t("No activity yet", "Aucune activité pour l'instant") }
    static var directMessage: String { t("Direct message…", "Message direct…") }
    static func teamMemberCount(_ n: Int) -> String {
        t("\(n) agent\(n == 1 ? "" : "s")", "\(n) agent\(n == 1 ? "" : "s")")
    }
    static var teamSetupHint: String {
        t("CLI agents (Claude Code, Codex, Cursor, Hermes…) must be installed, authenticated in Terminal, and Online on the Agents page before they can join a team. Keep-only teams work without external CLIs.",
          "Les agents CLI (Claude Code, Codex, Cursor, Hermes…) doivent être installés, authentifiés dans le Terminal, et En ligne sur la page Agents avant de rejoindre une équipe. Les équipes Keep seules fonctionnent sans CLI externe.")
    }
    static var teamCLIAuthHint: String {
        t("Many CLIs need a one-time login in Terminal first — e.g. run `claude` or `codex` and sign in, then tap Health check on the Agents page.",
          "Beaucoup de CLI exigent une connexion unique dans le Terminal — lancez par ex. `claude` ou `codex` et connectez-vous, puis Vérifier l’état sur la page Agents.")
    }
    static var teamSlotStarting: String {
        t("Starting agent…", "Démarrage de l’agent…")
    }
    static var teamMemberUnavailable: String {
        t("Not available for teams", "Indisponible pour les équipes")
    }
    static var agentsCLIAuthBanner: String {
        t("Tip: if Health check fails or a CLI is Offline, open Terminal and run the agent command once to sign in (e.g. `claude login`, `codex login`). Keep only verifies the CLI — it does not perform vendor authentication for you.",
          "Astuce : si Vérifier l’état échoue ou qu’un CLI est Hors ligne, ouvrez le Terminal et lancez la commande une fois pour vous connecter (ex. `claude login`, `codex login`). Keep vérifie seulement le CLI — il ne fait pas l’authentification à votre place.")
    }
    static var claudeSubscriptionNote: String {
        t("Claude Code uses your Anthropic account from Terminal login. Claude Pro/Max subscription may not apply to third-party apps — an API key may be required instead.",
          "Claude Code utilise votre compte Anthropic via la connexion Terminal. L’abonnement Claude Pro/Max peut ne pas s’appliquer aux apps tierces — une clé API peut être nécessaire.")
    }

    // MARK: - Remote access & bridges
    static var remoteAccess: String { t("Remote access", "Accès distant") }
    static var remoteAccessSubtitle: String {
        t("Reach your agents from other devices on this network. The backend restarts with authentication enabled.",
          "Accédez à vos agents depuis d'autres appareils du réseau. Le backend redémarre avec authentification.")
    }
    static var remoteEnableFailed: String {
        t("Could not restart the agent backend in remote mode.",
          "Impossible de redémarrer le backend agent en mode distant.")
    }
    static var remoteEnabled: String { t("Remote access on", "Accès distant activé") }
    static var remoteDisabled: String { t("Local only", "Local uniquement") }
    static var remoteURL: String { t("LAN address", "Adresse LAN") }
    static var remoteCredentials: String { t("Credentials", "Identifiants") }
    static var remoteQR: String { t("Pairing token", "Jeton d'appairage") }
    static var remoteRegenerateQR: String { t("New token", "Nouveau jeton") }
    static var username: String { t("Username", "Nom d'utilisateur") }
    static var password: String { t("Password", "Mot de passe") }
    static var copied: String { t("Copied", "Copié") }
    static var copy: String { t("Copy", "Copier") }
    static var chatBridges: String { t("Chat bridges", "Passerelles de chat") }
    static var chatBridgesSubtitle: String {
        t("Talk to your agents from Telegram and other platforms. Paste a bot token, then Enable.",
          "Parlez à vos agents depuis Telegram et d’autres plateformes. Collez un jeton de bot, puis Activer.")
    }
    static var chatBridgesEmpty: String {
        t("No bridges reported by the backend yet. Refresh, or check that Keep’s agent backend is running.",
          "Aucune passerelle renvoyée par le backend. Actualisez, ou vérifiez que le backend agent de Keep tourne.")
    }
    static var channelTokenRequired: String {
        t("Enter a bot token before enabling this bridge.",
          "Saisissez un jeton de bot avant d’activer cette passerelle.")
    }
    static var botToken: String { t("Bot token", "Jeton du bot") }
    static var channelTestFailed: String { t("Token test failed.", "Échec du test du jeton.") }
    static var channelEnable: String { t("Enable", "Activer") }
    static var channelDisable: String { t("Disable", "Désactiver") }
    static var channelConnected: String { t("Connected", "Connecté") }
    static var channelDisconnected: String { t("Disconnected", "Déconnecté") }
    static var pendingPairings: String { t("Pending pairings", "Appairages en attente") }
    static var approve: String { t("Approve", "Approuver") }
    static var reject: String { t("Reject", "Rejeter") }
    static var authorizedUsers: String { t("Authorized users", "Utilisateurs autorisés") }
    static var revoke: String { t("Revoke", "Révoquer") }

    // MARK: - Agent firewall synergies
    static var agentTrafficBadge: String { t("Keep agent traffic", "Trafic de l'agent Keep") }
    static var agentFirewall: String { t("Agent firewall", "Pare-feu de l'agent") }
    static var agentFirewallSubtitle: String {
        t("Control how the Cowork agent backend reaches the network.",
          "Contrôlez l'accès réseau du backend de l'agent Cowork.")
    }
    static var agentFirewallAllow: String { t("Always allow", "Toujours autoriser") }
    static var agentFirewallAsk: String { t("Ask each time", "Demander à chaque fois") }
    static var agentFirewallDeny: String { t("Block", "Bloquer") }
    static var agentFirewallNoRule: String { t("No rule", "Aucune règle") }
    static var imagePreviewFailed: String { t("Unable to load image preview.", "Impossible de charger l'image.") }
    static var pdfPreviewFailed: String { t("Unable to load PDF preview.", "Impossible de charger le PDF.") }
    static func diffTitle(_ name: String) -> String { t("Diff · \(name)", "Diff · \(name)") }

    // MARK: - Assistants

    static var assistantsTitle: String { t("Assistants", "Assistants") }
    static var assistantsSubtitle: String {
        t("Built-in specialists for PPT, Excel, image workflows, folder tasks, and more.",
          "Spécialistes intégrés pour PPT, Excel, images, dossiers, et plus.")
    }
    static var edit: String { t("Edit", "Modifier") }
    static var assistantName: String { t("Name", "Nom") }
    static var assistantDescription: String { t("Description", "Description") }
    static var systemPrompt: String { t("System prompt", "Consigne système") }
    static var enabled: String { t("Enabled", "Activé") }
    static var assistantBuiltinBadge: String { t("Built-in", "Intégré") }
    static var assistantRulesReadOnlyHelp: String {
        t("Built-in assistants use bundled rules and cannot be edited here. Duplicate the assistant to customize rules.",
          "Les assistants intégrés ont des règles embarquées non modifiables ici. Dupliquez l'assistant pour personnaliser les règles.")
    }
    static var assistantBuiltinRulesReadOnly: String {
        t("Built-in assistant rules are read-only.",
          "Les règles des assistants intégrés sont en lecture seule.")
    }
    static var mcpPickerMultiSelectHelp: String {
        t("Select one or more enabled MCP servers for this session.",
          "Sélectionnez un ou plusieurs serveurs MCP activés pour cette session.")
    }
    static var assistantBuiltinEnabledHelp: String {
        t("You can enable or disable this built-in assistant. Other fields are read-only.",
          "Vous pouvez activer ou désactiver cet assistant intégré. Les autres champs sont en lecture seule.")
    }
    static var assistantBuiltinGenericOverview: String {
        t("This built-in assistant ships with preset behavior. Enable it to use it in chats, teams, and scheduled tasks.",
          "Cet assistant intégré a un comportement prédéfini. Activez-le pour l'utiliser dans les chats, équipes et tâches planifiées.")
    }
    static var assistantAbout: String { t("About this assistant", "À propos de cet assistant") }
    static var close: String { t("Close", "Fermer") }
    static var assistantNameAgentSocial: String {
        t("Agent social network", "Réseau social d'agents")
    }
    static var assistantDescAgentSocial: String {
        t("A shared forum where your AI agents can post, comment, and interact with each other.",
          "Un forum partagé où vos agents IA peuvent publier, commenter et interagir entre eux.")
    }
    static var assistantOverviewAgentSocial: String {
        t("Connect an agent to a social network built for AI: register, publish posts, reply in threads, and browse communities — like Twitter or Reddit, but for agents talking to each other.",
          "Connectez un agent à un réseau social conçu pour l'IA : inscription, publications, réponses aux fils et exploration de communautés — comme Twitter ou Reddit, mais pour des agents qui dialoguent entre eux.")
    }
    static var recommendedPrompts: String { t("Suggested prompts", "Suggestions de prompts") }
    static var recommendedPromptsHelp: String {
        t("One prompt per line, shown as quick picks when starting a chat.",
          "Un prompt par ligne, proposés comme raccourcis au démarrage d'un chat.")
    }
    static var assistantLoadFailed: String {
        t("Could not load this assistant.", "Impossible de charger cet assistant.")
    }
    static var assistantNameRequired: String {
        t("Assistant name is required.", "Le nom de l'assistant est requis.")
    }

    // MARK: - MCP / Tools

    static var mcpTools: String { t("MCP Tools", "Outils MCP") }
    static var refresh: String { t("Refresh", "Actualiser") }
    static var mcpSubtitle: String {
        t("Model Context Protocol servers — image generation, web search, filesystem tools, and more.",
          "Serveurs MCP — génération d'images, recherche web, fichiers, et plus.")
    }
    static var mcpUsageHelp: String {
        t("Enable a server to expose its tools to agents. Skills below are documentation you can edit; Save rule writes the markdown and keeps this window open.",
          "Activez un serveur pour exposer ses outils aux agents. Les compétences ci-dessous sont de la documentation éditable ; Enregistrer la règle sauve le markdown sans fermer la fenêtre.")
    }
    static var installedServers: String { t("Installed servers", "Serveurs installés") }
    static var detectedAgents: String { t("Detected from agents", "Détectés depuis les agents") }
    static var importMcpJSON: String { t("Import MCP JSON", "Importer JSON MCP") }
    static var importMcpHelp: String {
        t("Advanced: paste a Cursor/Claude `mcp.json` fragment or server list.",
          "Avancé : collez un fragment `mcp.json` ou une liste de serveurs.")
    }
    static var importJSON: String { t("Import JSON", "Importer JSON") }
    static var importing: String { t("Importing…", "Importation…") }
    static var importAction: String { t("Import", "Importer") }
    static var builtin: String { t("built-in", "intégré") }
    static var mcpEmpty: String {
        t("No MCP servers installed yet. Import from detected agents below, or paste JSON.",
          "Aucun serveur MCP. Importez depuis les agents détectés ou collez du JSON.")
    }
    static var mcpDetectedEmpty: String {
        t("No MCP configs detected from Claude Code or other local agents.",
          "Aucune config MCP détectée depuis les agents locaux.")
    }
    static var skillsHub: String { t("Skills hub", "Centre de compétences") }
    static var skillsHubHelp: String {
        t("View assistant rules and skill documentation. Built-in assistant rules are read-only — duplicate an assistant to customize.",
          "Consulter les règles d'assistant et la documentation des compétences. Les règles intégrées sont en lecture seule — dupliquez un assistant pour les modifier.")
    }

    // MARK: - Skills / permissions

    static var skills: String { t("Skills", "Compétences") }
    static func skillsCount(_ count: Int) -> String {
        count == 0 ? skills : t("Skills · \(count)", "Compétences · \(count)")
    }
    static var skillsHelp: String {
        t("Optional agent skills for this session",
          "Compétences optionnelles pour cette session")
    }
    static var skillsExtend: String {
        t("Skills extend what the agent can do for this chat.",
          "Les compétences étendent les capacités de l'agent pour ce chat.")
    }
    static var sessionSkillsPickerHelp: String {
        t("Toggle skill packages for this chat session. To read or edit skill docs and assistant rules, open Tools → MCP.",
          "Activez des compétences pour ce chat. Pour lire ou modifier la doc et les règles, ouvrez Outils → MCP.")
    }
    static var mcpSkillsHubSectionHelp: String {
        t("Documentation & rules — not session toggles. Use the Skills chip in a chat to enable skills per session.",
          "Documentation et règles — pas les toggles de session. Utilisez la puce Compétences dans un chat.")
    }
    static var skillDetailNewsletterHiring: String {
        t("Publish Infomaniak hiring posts with copy guidelines, visuals, and automation.",
          "Publier des offres d'emploi Infomaniak avec consignes rédactionnelles, visuels et automatisation.")
    }
    static var skillDetailKDriveShare: String {
        t("Share files from kDrive via secure links.",
          "Partager des fichiers kDrive via des liens sécurisés.")
    }
    static var skillDetailOfficeAutomation: String {
        t("Create and edit Office documents — Word, Excel, and PowerPoint.",
          "Créer et modifier des documents Office — Word, Excel et PowerPoint.")
    }
    static var skillDetailSkillCreator: String {
        t("Author new agent skills with guided templates.",
          "Créer de nouvelles compétences d'agent avec des modèles guidés.")
    }
    static var skillDetailScheduledTasks: String {
        t("Schedule recurring agent tasks.",
          "Planifier des tâches d'agent récurrentes.")
    }
    static var skillDetailStoryRoleplay: String {
        t("Interactive creative writing and character play.",
          "Écriture créative interactive et jeu de rôle.")
    }
    static var skillDetailRemoteAgentSetup: String {
        t("Configure remote agents, tools, and integrations.",
          "Configurer des agents distants, outils et intégrations.")
    }
    static var skillDetailCoworkConfig: String {
        t("Tune Cowork workspace and agent defaults.",
          "Ajuster l'espace de travail Cowork et les paramètres d'agent.")
    }
    static var skillDetailMorphPPT: String {
        t("Create polished presentations with smooth slide morph animations.",
          "Créer des présentations soignées avec des transitions morph entre diapositives.")
    }
    static var skillDetailMorphPPT3D: String {
        t("Build PowerPoint decks with 3D morph transitions between slides.",
          "Créer des présentations PowerPoint avec transitions morph 3D.")
    }
    static var skillDetailMermaid: String {
        t("Diagrams and flowcharts using Mermaid syntax.",
          "Diagrammes et organigrammes en syntaxe Mermaid.")
    }
    static var skillDetailMoltbook: String {
        t("Post, comment, and interact on the agent social network.",
          "Publier, commenter et interagir sur le réseau social d'agents.")
    }
    static var skillDetailTroubleshooting: String {
        t("Diagnose and fix common Cowork setup issues.",
          "Diagnostiquer et corriger les problèmes courants de configuration Cowork.")
    }
    static var skillDetailWebUIPublic: String {
        t("Expose Cowork over the network for remote browser access.",
          "Exposer Cowork sur le réseau pour un accès navigateur distant.")
    }
    static var skillDetailWebUISetup: String {
        t("Configure WebUI access, authentication, and remote login.",
          "Configurer l'accès WebUI, l'authentification et la connexion à distance.")
    }
    static var skillDetailPDF: String {
        t("Read, extract, and summarize PDF documents.",
          "Lire, extraire et résumer des documents PDF.")
    }
    static var skillDetailOfficePPT: String {
        t("PowerPoint presentations — outlines, slides, and exports.",
          "Présentations PowerPoint — plans, diapositives et exports.")
    }
    static var skillDetailOfficeExcel: String {
        t("Spreadsheets, formulas, charts, and data dashboards.",
          "Feuilles de calcul, formules, graphiques et tableaux de bord.")
    }
    static var skillDetailOfficeWord: String {
        t("Long-form documents, reports, and formatted Word files.",
          "Documents longs, rapports et fichiers Word formatés.")
    }
    static var skillContentUnavailable: String {
        t("This skill's documentation is not available in your language.",
          "La documentation de cette compétence n'est pas disponible dans votre langue.")
    }
    static func permissionsTitle(_ mode: String) -> String {
        t("Permissions · \(mode)", "Permissions · \(mode)")
    }
    static var permStandard: String { t("Standard", "Standard") }
    static var permAutoEdits: String { t("Auto-accept edits", "Accepter les modifications") }
    static var permFullAuto: String { t("Full auto", "Automatique total") }
    static var permPlanOnly: String { t("Plan only", "Plan uniquement") }
    static var permStandardDetail: String {
        t("Ask before shell, file, or network actions.",
          "Demander avant shell, fichiers ou réseau.")
    }
    static var permAutoEditsDetail: String {
        t("Approve workspace file edits automatically.",
          "Approuver automatiquement les modifications de fichiers.")
    }
    static var permFullAutoDetail: String {
        t("Run tools without prompts. Use only if you trust the agent.",
          "Exécuter les outils sans confirmation. Uniquement si vous faites confiance à l'agent.")
    }
    static var permPlanDetail: String {
        t("Draft a plan without executing tools.",
          "Rédiger un plan sans exécuter d'outils.")
    }

    // MARK: - Agents

    static var agentHealth: String { t("Health check", "Vérifier l'état") }
    static var connectAgent: String { t("Connect agent", "Connecter") }
    static var agentHealthy: String { t("Agent healthy", "Agent opérationnel") }
    static var agentUnhealthy: String { t("Agent unhealthy", "Agent défaillant") }
    static var managedAgents: String { t("Managed agents", "Agents gérés") }
    static var noAgents: String { t("No agents configured.", "Aucun agent configuré.") }

    // MARK: - Models

    static var noModelSelected: String { t("No model selected", "Aucun modèle sélectionné") }
    static var selectModelFirst: String { t("Select a model first.", "Sélectionnez d'abord un modèle.") }
    static var selectModel: String { t("Select model", "Choisir un modèle") }
    static var noAssistant: String { t("No assistant available.", "Aucun assistant disponible.") }
    static var coreNotReady: String {
        t("Keep is still starting. Wait a moment and try again.", "Keep démarre encore. Patientez un instant et réessayez.")
    }
    static var emptyMessage: String { t("Type a message first.", "Saisissez un message d'abord.") }
    static var mlxStartFailed: String {
        t(
            "Could not start the on-device MLX server. Check that the model is installed, then try again.",
            "Impossible de démarrer le serveur MLX local. Vérifiez que le modèle est installé, puis réessayez."
        )
    }
    static var mlxIncompleteDownloadHint: String {
        t(
            "The on-disk weights look incomplete. Open Models, delete the partial download, then download again.",
            "Les poids sur disque semblent incomplets. Ouvrez Modèles, supprimez le téléchargement partiel, puis retéléchargez."
        )
    }
    static var mlxModelNotInstalled: String {
        t(
            "This MLX model is not fully downloaded. Open Models and download it first.",
            "Ce modèle MLX n'est pas entièrement téléchargé. Ouvrez Modèles et téléchargez-le d'abord."
        )
    }
    static var mlxWarmingUp: String {
        t("Loading on-device model…", "Chargement du modèle local…")
    }
    static var manageProviders: String { t("Manage providers…", "Gérer les fournisseurs…") }
    static var addModelProvider: String { t("Add model provider", "Ajouter un fournisseur") }
    static var modelProviders: String { t("Model providers", "Fournisseurs de modèles") }
    static var ollamaReachable: String { t("Ollama reachable", "Ollama accessible") }
    static var ollamaOffline: String { t("Ollama offline", "Ollama hors ligne") }
    static var ollamaNoModels: String { t("No chat models found in Ollama.", "Aucun modèle de chat dans Ollama.") }
    static var ollamaNotReachable: String {
        t("Ollama not reachable at 127.0.0.1:11434",
          "Ollama inaccessible sur 127.0.0.1:11434")
    }
    static var providersHelp: String {
        t("Connect Ollama, MLX, OpenAI, Anthropic, or other model providers",
          "Connecter Ollama, MLX, OpenAI, Anthropic ou d'autres fournisseurs")
    }

    // MARK: - Cloud BYOK models

    static func cloudModelsTitle(_ name: String) -> String {
        t("\(name) models", "Modèles \(name)")
    }
    static var cloudModelsSubtitle: String {
        t("Select which models to enable for chat", "Choisissez les modèles activés pour le chat")
    }
    static var enableAll: String { t("Enable all", "Tout activer") }
    static var disableAll: String { t("Disable all", "Tout désactiver") }
    static var loadingModels: String { t("Loading models…", "Chargement des modèles…") }
    static var modelsLoadFailed: String { t("Failed to load models", "Échec du chargement des modèles") }
    static var noModelsFound: String { t("No models found", "Aucun modèle trouvé") }
    static var saveSelection: String { t("Save selection", "Enregistrer la sélection") }
    static var apiKeyRequired: String { t("API key required", "Clé API requise") }
    static var continueToModels: String { t("Continue to models", "Continuer vers les modèles") }
    static var cloudProvidersSection: String { t("Cloud (BYOK)", "Cloud (BYOK)") }
    static var cloudTab: String { t("Cloud", "Cloud") }
    static var localProvidersSection: String { t("Local", "Local") }
    static var noCloudProviders: String { t("No cloud providers", "Aucun fournisseur cloud") }
    static var noCloudProvidersDetail: String {
        t("Add OpenAI, Anthropic, xAI, Infomaniak, or another API to get started.",
          "Ajoutez OpenAI, Anthropic, xAI, Infomaniak ou une autre API pour commencer.")
    }
    static var manageModels: String { t("Models…", "Modèles…") }
    static func modelsCount(_ n: Int) -> String { t("\(n) models", "\(n) modèles") }
    static func modelsEnabledCount(_ enabled: Int, _ total: Int) -> String {
        t("\(enabled) of \(total) models enabled", "\(enabled) modèles sur \(total) activés")
    }
    static func contextTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return t("\(count / 1_000_000)M ctx", "\(count / 1_000_000)M ctx")
        }
        if count >= 1_000 {
            return t("\(count / 1_000)k ctx", "\(count / 1_000)k ctx")
        }
        return t("\(count) ctx", "\(count) ctx")
    }
    static var contextWindow: String { t("Context window", "Fenêtre de contexte") }
    static var pricing: String { t("Pricing", "Tarification") }
    static var modelIDLabel: String { t("Model ID", "ID modèle") }
    static var descriptionLabel: String { t("Description", "Description") }
    static func pricingInputOutput(_ input: Double, _ output: Double) -> String {
        t("Input $\(String(format: "%.2f", input)) / Output $\(String(format: "%.2f", output)) per 1M",
          "Entrée $\(String(format: "%.2f", input)) / Sortie $\(String(format: "%.2f", output)) par 1M")
    }
    static var infomaniakProductIdLabel: String { t("Product ID (optional)", "ID produit (optionnel)") }
    static var infomaniakProductIdPlaceholder: String { t("e.g. 12345", "ex. 12345") }
    static var infomaniakProductIdHelp: String {
        t("Leave empty to auto-discover all kAI products on your Infomaniak account.",
          "Laissez vide pour découvrir automatiquement tous les produits kAI du compte.")
    }
    static var infomaniakNoProducts: String {
        t("No AI products found on this Infomaniak account.", "Aucun produit IA sur ce compte Infomaniak.")
    }

    // MARK: - BYOK cost control

    static var costControlTitle: String { t("AI Models Cost Control", "Contrôle des coûts IA") }
    static var costControlSubtitle: String {
        t("Cap output tokens for BYOK cloud models to limit cost spikes.",
          "Plafonnez les jetons de sortie des modèles cloud BYOK pour limiter les pics de coût.")
    }
    static var costControlHowTitle: String { t("How this works", "Comment ça marche") }
    static var costControlHowBody: String {
        t("Step 1: set a default cap (optional).\nStep 2: enable per-model caps for your cloud models. Model caps override the default.",
          "Étape 1 : plafond par défaut (optionnel).\nÉtape 2 : plafonds par modèle cloud. Ils remplacent le défaut.")
    }
    static var costControlDefaultLabel: String { t("Default max output tokens", "Jetons de sortie max (défaut)") }
    static var costControlDefaultPlaceholder: String { t("e.g. 1200", "ex. 1200") }
    static var costControlDetectedLabel: String {
        t("Enabled cloud models (custom caps)", "Modèles cloud activés (plafonds)")
    }
    static var costControlNoModels: String {
        t("No enabled cloud models yet. Configure providers and enable models first.",
          "Aucun modèle cloud activé. Configurez d'abord vos fournisseurs et modèles.")
    }
    static var costControlCapPlaceholder: String { t("cap", "plafond") }
    static var costControlFast: String { t("Fast", "Rapide") }
    static var costControlSafe: String { t("Safe", "Sûr") }
    static var costControlSave: String { t("Save BYOK token limits", "Enregistrer les plafonds BYOK") }
    static var estimatedCost: String { t("Est. cost", "Coût est.") }

    // MARK: - Conversation usage

    static var totalTokens: String { t("Total tokens", "Jetons totaux") }
    static var avgPerTurn: String { t("Avg / turn", "Moy. / tour") }
    static var turns: String { t("Turns", "Tours") }
    static var modelsUsed: String { t("Models used", "Modèles utilisés") }
    static var providersUsed: String { t("Providers used", "Fournisseurs utilisés") }
    static func usageHelp(_ input: Int, _ output: Int, _ turns: Int) -> String {
        t("Input \(input) · Output \(output) · \(turns) turns",
          "Entrée \(input) · Sortie \(output) · \(turns) tours")
    }
    static var useFolder: String { t("Use Folder", "Utiliser le dossier") }
    static var attachFiles: String { t("Attach", "Joindre") }

    // MARK: - Home

    static var coreStarting: String { t("Starting Keep…", "Démarrage de Keep…") }
    static var coreOffline: String { t("Keep engine offline", "Moteur Keep hors ligne") }
    static var loadingKeepCatalog: String {
        t("Loading Keep workspace…", "Chargement de l’espace Keep…")
    }
    static var sendingMessage: String { t("Sending message…", "Envoi du message…") }
    static var checkingAgentHealth: String {
        t("Checking agent health…", "Vérification de l’agent…")
    }
    static func checkingAgents(_ n: Int) -> String {
        t("Checking \(n) agents…", "Vérification de \(n) agents…")
    }
    static var enablingRemoteAccess: String {
        t("Updating remote access…", "Mise à jour de l’accès distant…")
    }
    static var teamCreating: String { t("Creating team…", "Création de l’équipe…") }
    static var teamOpening: String { t("Opening team workspace…", "Ouverture de l’équipe…") }
    static var teamAddingMember: String { t("Adding team member…", "Ajout du membre…") }
    static var teamSendingTask: String { t("Sending team task…", "Envoi de la tâche d’équipe…") }
    static var homeGreeting: String { t("What should Keep do?", "Que doit faire Keep ?") }
    static var homeTagline: String {
        t("Agents can read files, write drafts, organize folders, and more — you stay in control.",
          "Les agents lisent des fichiers, rédigent, organisent des dossiers, et plus — vous gardez le contrôle.")
    }
    static var connectModel: String { t("First: connect a model", "D’abord : connectez un modèle") }
    static var connectModelDetail: String {
        t("Keep needs a brain. Add a local model (Ollama / LM Studio / on-device) or a cloud key. Nothing runs until this step is done.",
          "Keep a besoin d’un modèle. Ajoutez un modèle local (Ollama / LM Studio / sur l’appareil) ou une clé cloud. Rien ne démarre avant cette étape.")
    }
    static var hintImages: String { t("Image generation", "Génération d'images") }
    static var hintFolders: String { t("Folder organize", "Organisation de dossiers") }
    static var hintCode: String { t("Code & docs", "Code et documents") }
    static func toolsCount(_ n: Int) -> String { t("\(n) tools", "\(n) outils") }
    static func permissionsChip(_ mode: String) -> String { permissionsTitle(mode) }

    // MARK: - Tool capability

    static var chatOnly: String { t("Chat only", "Chat seul") }
    static var toolsAvailable: String { t("Tools", "Outils") }
    static var mcpOff: String { t("MCP · off", "MCP · désactivé") }
    static var skillsOff: String { t("Skills · off", "Compétences · désactivées") }
    static var chatOnlyModeNotice: String {
        t(
            "Conversation mode — this model answers without tools (files, shell, MCP unavailable).",
            "Mode conversation — ce modèle répond sans outils (fichiers, shell, MCP indisponibles)."
        )
    }
    static var chatOnlyPresetContext: String {
        t(
            """
            You are in chat-only mode. You cannot execute tools, run shell commands, or use MCP servers. \
            When the user message includes document excerpts (between --- filename --- markers), answer from that content. \
            If no document text is included and the user asks about file contents, say you need them to attach the file or use a tool-capable model.
            """,
            """
            Tu es en mode conversation seule. Tu ne peux pas exécuter d'outils, lancer de commandes shell ni utiliser de serveurs MCP. \
            Quand le message inclut des extraits de documents (entre marqueurs --- nom de fichier ---), réponds à partir de ce contenu. \
            Sans texte de document inclus, dis qu'il faut joindre le fichier ou utiliser un modèle compatible outils.
            """
        )
    }
    static func toolsDisabledForModel(_ name: String) -> String {
        t(
            "Tools and MCP are disabled for \(name) — this model does not support tool calling. Plain chat still works.",
            "Outils et MCP désactivés pour \(name) — ce modèle ne gère pas les outils. Le chat simple fonctionne."
        )
    }
    static var toolsDisabledMcpHelp: String {
        t("MCP tools require a model with tool support (e.g. qwen3.6).",
          "Les outils MCP nécessitent un modèle compatible outils (ex. qwen3.6).")
    }
    static var toolsDisabledSkillsHelp: String {
        t("Agent skills require a model with tool support.",
          "Les compétences nécessitent un modèle compatible outils.")
    }
    static var noMcpServers: String { t("No MCP servers", "Aucun serveur MCP") }
    static var manageMcp: String { t("Manage MCP tools…", "Gérer les outils MCP…") }
    static var mcpToolsLabel: String { t("MCP tools", "Outils MCP") }
    static func mcpCount(_ count: Int) -> String {
        count == 0 ? mcpToolsLabel : t("MCP · \(count)", "MCP · \(count)")
    }

    // MARK: - Errors (backend + local)

    static func localizeError(_ raw: String, providerPlatform: String? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        let lower = trimmed.lowercased()
        if (lower.contains("avec ollama") || lower.contains("with ollama") || lower.contains("qwen3.6"))
            && providerPlatform?.lowercased() != "ollama" {
            return providerRejectedError(platform: providerPlatform)
        }
        if lower.contains("model provider rejected the request") {
            return providerRejectedError(platform: providerPlatform)
        }
        if lower.contains("provider rejected") || lower.contains("rejected the request") {
            return providerRejectedError(platform: providerPlatform)
        }
        if lower.contains("model was not found") || lower.contains("model not found") {
            return t("The selected model was not found. Choose an available model and retry.",
                     "Le modèle sélectionné est introuvable. Choisissez un modèle disponible et réessayez.")
        }
        if lower.contains("rate limit") {
            return t("Model provider rate limit reached. Wait and retry.",
                     "Limite du fournisseur atteinte. Attendez et réessayez.")
        }
        if lower.contains("context") && (lower.contains("too large") || lower.contains("limit")) {
            return t("Context is too large for this model. Shorten the message or history.",
                     "Le contexte est trop volumineux pour ce modèle. Réduisez le message ou l'historique.")
        }
        if lower.contains("tool schema") || lower.contains("invalid tool") {
            if providerPlatform?.lowercased() != "ollama" {
                return t(
                    "The provider rejected an MCP tool schema. Citadel curates schemas automatically — try fewer MCP servers (avoid Chrome DevTools on cloud) or retry.",
                    "Le fournisseur a rejeté un schéma d'outil MCP. Citadel filtre les schémas — essayez moins de serveurs MCP (évitez Chrome DevTools en cloud) ou réessayez."
                )
            }
            return t("The model rejected a tool definition. Try a model with tool support (e.g. qwen3.6).",
                     "Le modèle a rejeté une définition d'outil. Essayez un modèle compatible outils (ex. qwen3.6).")
        }
        if lower.contains("could not reach") || lower.contains("connection refused") || lower.contains("network") {
            return t("Could not reach the model provider. Check that Ollama or the API is running.",
                     "Impossible de joindre le fournisseur. Vérifiez qu'Ollama ou l'API est démarré.")
        }
        if lower.contains("api key") || lower.contains("unauthorized") || lower.contains("authentication") {
            return t("Provider credentials were rejected. Check API keys in provider settings.",
                     "Identifiants rejetés. Vérifiez les clés API dans les paramètres fournisseur.")
        }
        return trimmed
    }

    static func providerRejectedError(platform: String? = nil) -> String {
        if platform?.lowercased() == "ollama" {
            return t(
                "The model provider rejected the request. For Ollama, use a model with tool support (e.g. qwen3.6:latest). Simpler models like Gemma may fail when tools or MCP are enabled.",
                "Le fournisseur a rejeté la requête. Avec Ollama, utilisez un modèle compatible outils (ex. qwen3.6:latest). Les modèles simples comme Gemma échouent souvent avec les outils ou MCP activés."
            )
        }
        return t(
            "The cloud provider rejected the request. Citadel curates MCP tool schemas (Cursor-style), but some servers still expose incompatible definitions. The model (GPT, Claude, Gemini…) is usually fine.",
            "Le fournisseur cloud a rejeté la requête. Citadel filtre les schémas MCP (style Cursor), mais certains serveurs exposent encore des définitions incompatibles. Le modèle (GPT, Claude, Gemini…) est en général OK."
        )
    }

    static func providerRejectedHint(platform: String? = nil, mcpCount: Int = 0) -> String {
        if platform?.lowercased() == "ollama" {
            return t(
                "Suggestion: switch to qwen3.6 or disable extra MCP servers, then retry.",
                "Suggestion : passez à qwen3.6 ou désactivez les serveurs MCP, puis réessayez."
            )
        }
        if mcpCount > 0 {
            return t(
                "Suggestion: disable heavy MCP servers (e.g. Chrome DevTools) or set MCP · 0, then retry. Citadel auto-retries without MCP when needed.",
                "Suggestion : désactivez les serveurs MCP lourds (ex. Chrome DevTools) ou passez MCP · 0, puis réessayez. Citadel réessaie sans MCP si besoin."
            )
        }
        return t(
            "Check the API key, model name, and billing on the provider side.",
            "Vérifiez la clé API, le nom du modèle et la facturation côté fournisseur."
        )
    }

    static var providerRejectedError: String { providerRejectedError(platform: nil) }

    static var providerRejectedHint: String { providerRejectedHint(platform: nil, mcpCount: 0) }

    static func mcpCuratedDropNotice(_ serverNames: String) -> String {
        t(
            "Some MCP servers were skipped for this cloud model (incompatible or too many tools): \(serverNames).",
            "Certains serveurs MCP ont été ignorés pour ce modèle cloud (schémas incompatibles ou trop d'outils) : \(serverNames)."
        )
    }

    // MARK: - Fortress (network)

    /// Product name — kept as brand in both languages.
    static var fortress: String { t("Fortress", "Fortress") }
    static var fortressActivity: String { t("Activity", "Activité") }
    static var fortressSuspects: String { t("Suspects", "Suspects") }
    static var fortressHistory: String { t("History", "Historique") }
    static var fortressRules: String { t("Rules", "Règles") }
    static var fortressSettings: String { t("Settings", "Réglages") }
    static var fortressNetworkActivity: String {
        t("Fortress · Network activity", "Fortress · Activité réseau")
    }
    static var fortressSuspectsTitle: String { t("Fortress · Suspects", "Fortress · Suspects") }
    static var fortressHistoryTitle: String { t("Fortress · History", "Fortress · Historique") }
    static var fortressRulesTitle: String { t("Fortress · Rules", "Fortress · Règles") }
    static var fortressSettingsTitle: String { t("Fortress · Settings", "Fortress · Réglages") }

    static var fortressHelpTitle: String { t("Fortress guide", "Guide Fortress") }
    static var fortressHelpShort: String { t("Guide", "Guide") }
    static var fortressHelpSearch: String { t("Search help…", "Rechercher dans l’aide…") }
    static var fortressHelpPick: String { t("Choose a topic on the left.", "Choisissez un sujet à gauche.") }
    static var fortressHelpNoResults: String { t("No matching articles.", "Aucun article correspondant.") }
    static func fortressHelpForPage(_ page: String) -> String {
        t("Suggested for \(page)", "Suggéré pour \(page)")
    }

    static var localFortress: String { t("Watching locally", "Surveillance locale") }
    static var fortressDemo: String { t("Fortress demo", "Démo Fortress") }
    static var fortressIdle: String { t("Fortress idle", "Fortress inactif") }
    static var helperActive: String { t("Privileged helper on", "Assistant privilégié actif") }
    static var helperOfflineBanner: String {
        t("Background helper offline — some rules and real website names need it.",
          "Assistant d’arrière-plan hors ligne — certaines règles et vrais noms de sites en ont besoin.")
    }
    static var helperActiveSubtitle: String {
        t("Live network view and firewall actions are available.",
          "Vue réseau en direct et actions pare-feu disponibles.")
    }
    static var fortressDemoSubtitle: String {
        t("Sample traffic with grouped Cursor helpers.",
          "Trafic d’exemple avec les helpers Cursor regroupés.")
    }

    static var protectionStatus: String { t("Protection", "Protection") }
    static var protectionActive: String { t("Protection active", "Protection active") }
    static var protectionFilterOnly: String {
        t("Filter on — helper reconnecting", "Filtre actif — reconnexion de l’assistant")
    }
    static var protectionNeedsApproval: String {
        t("Waiting for macOS approval", "En attente d’approbation macOS")
    }
    static var protectionActivating: String { t("Starting protection…", "Démarrage de la protection…") }
    static var protectionLocalMode: String {
        t("Local mode (no per-app filter yet)", "Mode local (pas encore de filtre par app)")
    }
    static var protectionLimited: String { t("Limited protection", "Protection limitée") }
    static var protectionHelp: String {
        t("Full protection needs macOS approval for Citadel’s network filter. Until then, Fortress can still show activity.",
          "La protection complète nécessite l’approbation macOS pour le filtre réseau de Citadel. En attendant, Fortress peut toujours montrer l’activité.")
    }
    static var askTimeoutDeny: String {
        t("If you don’t answer an alert in time, block the connection",
          "Si vous ne répondez pas à temps à une alerte, bloquer la connexion")
    }

    static var alertScopeAny: String { t("Any connection from this app", "Toute connexion de cette app") }
    static var alertScopeHost: String { t("This website / host only", "Ce site / hôte seulement") }
    static var alertScopeIPPort: String { t("This IP and port only", "Cette IP et ce port seulement") }
    static var alertDurationForever: String { t("Forever", "Pour toujours") }
    static var alertDurationSession: String { t("Until I quit Citadel", "Jusqu’à la fermeture de Citadel") }
    static var alertDuration1h: String { t("1 hour", "1 heure") }
    static var alertDuration24h: String { t("24 hours", "24 heures") }
    static var wantsToConnect: String { t("wants to connect to", "veut se connecter à") }
    static var unknownProcess: String { t("Unknown app", "App inconnue") }
    static func signedByTeam(_ team: String) -> String {
        t("Signed · Team \(team)", "Signée · Team \(team)")
    }
    static var signedValid: String { t("Signed and valid", "Signée et valide") }
    static var signedInvalid: String { t("Invalid signature", "Signature invalide") }
    static var unsignedBinary: String { t("Not code-signed", "Non signée") }
    static var signingUnknown: String { t("Signature unknown", "Signature inconnue") }
    static var signing: String { t("Signing", "Signature") }
    static var teamID: String { t("Team ID", "Team ID") }

    static var suspectsTitle: String { t("Suspicious communications", "Communications suspectes") }
    static var suspectsSubtitle: String {
        t("Clear reasons only — unsigned apps, first-time destinations, sensitive ports, and more.",
          "Raisons claires seulement — apps non signées, destinations inédites, ports sensibles, etc.")
    }
    static var suspectsEmptyTitle: String { t("Nothing suspicious right now", "Rien de suspect pour l’instant") }
    static var suspectsEmptyBody: String {
        t("Fortress lists only hard, checkable signals. When something looks off, it appears here with a plain-language why.",
          "Fortress ne liste que des signaux durs et vérifiables. Quand quelque chose cloche, ça apparaît ici avec un pourquoi en langage clair.")
    }
    static var suspectsWhy: String { t("Why is this listed?", "Pourquoi c’est listé ?") }
    static var suspectsShowInActivity: String { t("Show in Activity", "Voir dans Activité") }
    static var suspectSeverityAlert: String { t("Alert", "Alerte") }
    static var suspectSeverityWatch: String { t("Watch", "Vigilance") }
    static var suspectSeverityInfo: String { t("Info", "Info") }

    static var historyTitle: String { t("Connection history", "Historique des connexions") }
    static var historySubtitle: String {
        t("Recent connections kept on this Mac (default 7 days).",
          "Connexions récentes conservées sur ce Mac (7 jours par défaut).")
    }
    static var historyEmpty: String { t("No history yet.", "Pas encore d’historique.") }
    static var historyPeriod: String { t("Period", "Période") }
    static var history1d: String { t("Last day", "Dernier jour") }
    static var history7d: String { t("Last 7 days", "7 derniers jours") }
    static var history30d: String { t("Last 30 days", "30 derniers jours") }
    static var historyFilterApp: String { t("Filter app…", "Filtrer l’app…") }
    static var historyFilterHost: String { t("Filter host…", "Filtrer l’hôte…") }
    static var exportCSV: String { t("Export CSV", "Exporter CSV") }

    static var dnsFilterExplain: String {
        t("When on, Citadel filters domain names (ads, trackers, blocklists) before apps connect.",
          "Quand c’est activé, Citadel filtre les noms de domaine (pubs, trackers, blocklists) avant que les apps se connectent.")
    }
    static var blocklistsExplain: String {
        t("Enable lists to block known bad or noisy domains at DNS.",
          "Activez des listes pour bloquer des domaines connus (mauvais ou bruyants) au DNS.")
    }
    static var blocklistsEmpty: String {
        t("No blocklists loaded yet. They appear after the helper starts.",
          "Aucune blocklist chargée. Elles apparaissent après le démarrage de l’assistant.")
    }
    static var profilesExplain: String {
        t("A profile switches how strict Fortress is (ask, allow quietly, or deny quietly).",
          "Un profil change la sévérité de Fortress (demander, autoriser en silence, ou refuser en silence).")
    }

    static var startingTelemetry: String { t("Starting telemetry…", "Démarrage de la télémétrie…") }
    static var loadDemo: String { t("Load demo", "Charger la démo") }
    static var exitDemo: String { t("Exit demo", "Quitter la démo") }

    static var connectionRequest: String { t("Connection request", "Demande de connexion") }
    static var allow: String { t("Allow", "Autoriser") }
    static var deny: String { t("Deny", "Refuser") }
    static var rememberAllow: String { t("Remember Allow", "Mémoriser Autoriser") }
    static var rememberDeny: String { t("Remember Deny", "Mémoriser Refuser") }
    static var allow1h: String { t("Allow 1h", "Autoriser 1 h") }
    static var deny1h: String { t("Deny 1h", "Refuser 1 h") }
    static var rememberAllowShort: String { t("Remember allow", "Mémoriser autoriser") }
    static var rememberDenyShort: String { t("Remember deny", "Mémoriser refuser") }

    static var searchAppsHosts: String {
        t("Search apps, hosts, IPs…", "Rechercher apps, hôtes, IP…")
    }
    static var viewLabel: String { t("View", "Vue") }
    static var hideHelpers: String { t("Hide helpers", "Masquer les helpers") }
    static var activeOnly: String { t("Active only", "Actifs seulement") }
    static var grouped: String { t("Grouped", "Groupé") }
    static var flat: String { t("Flat", "Plat") }

    static var apps: String { t("Apps", "Apps") }
    static var allApps: String { t("All Apps", "Toutes les apps") }
    static var summary: String { t("Summary", "Résumé") }
    static var stream: String { t("Stream", "Flux") }
    static var streams: String { t("streams", "flux") }
    static var destinations: String { t("Destinations", "Destinations") }
    static var topApps: String { t("Top Apps", "Top apps") }
    static var topSites: String { t("Top Sites", "Top sites") }
    static var sites: String { t("Sites", "Sites") }
    static var topCountries: String { t("Top Countries", "Top pays") }
    static var noDataYet: String { t("No data yet", "Pas encore de données") }
    static var trafficDown: String { t("down", "desc.") }
    static var trafficUp: String { t("up", "mont.") }
    static var firewall: String { t("Firewall", "Pare-feu") }
    static var copyDetails: String { t("Copy details", "Copier les détails") }
    static var helperRememberOffline: String {
        t("Helper offline — remember-rules sync when helper is approved.",
          "Helper hors ligne — les règles mémorisées se synchronisent quand le helper est approuvé.")
    }

    static var process: String { t("Process", "Processus") }
    static var family: String { t("Family", "Famille") }
    static var role: String { t("Role", "Rôle") }
    static var remote: String { t("Remote", "Distant") }
    static var host: String { t("Host", "Hôte") }
    static var port: String { t("Port", "Port") }
    static var protocolLabel: String { t("Protocol", "Protocole") }
    static var status: String { t("Status", "État") }
    static var location: String { t("Location", "Lieu") }
    static var rateDown: String { t("↓ Rate", "↓ Débit") }
    static var rateUp: String { t("↑ Rate", "↑ Débit") }

    static var all: String { t("All", "Tout") }
    static var ask: String { t("Ask", "Demander") }
    static var temporary: String { t("Temporary", "Temporaire") }
    static var fromActivity: String { t("From activity", "Depuis l’activité") }
    static var showSuggestions: String { t("Show suggestions", "Afficher les suggestions") }
    static var helperRulesOffline: String {
        t("Helper offline — rules save when helper connects, or apply locally in demo.",
          "Helper hors ligne — les règles s’enregistrent à la connexion du helper, ou en local en démo.")
    }
    static var searchRules: String { t("Search rules…", "Rechercher des règles…") }
    static var newRule: String { t("New rule", "Nouvelle règle") }
    static var suggestedFromActivity: String {
        t("Suggested from live activity", "Suggestions depuis l’activité")
    }
    static var noRulesYet: String { t("No rules yet", "Aucune règle pour l’instant") }
    static var noRulesHint: String {
        t("Create a rule, or accept a suggestion from live Fortress activity.",
          "Créez une règle, ou acceptez une suggestion depuis l’activité Fortress.")
    }
    static var createFirstRule: String { t("Create your first rule", "Créer votre première règle") }
    static var inspector: String { t("Inspector", "Inspecteur") }
    static var ruleDetail: String { t("Rule detail", "Détail de la règle") }
    static var inspectorEmptyHint: String {
        t("Select a rule to inspect or fine-tune it. Suggestions appear from apps and destinations currently active in Fortress.",
          "Sélectionnez une règle pour l’inspecter ou l’affiner. Les suggestions viennent des apps et destinations actives dans Fortress.")
    }
    static var disable: String { t("Disable", "Désactiver") }
    static var enable: String { t("Enable", "Activer") }
    static var duplicateEdit: String { t("Duplicate & edit", "Dupliquer et modifier") }
    static var remove: String { t("Remove", "Supprimer") }
    static var disabled: String { t("Disabled", "Désactivée") }
    static var cancel: String { t("Cancel", "Annuler") }
    static var action: String { t("Action", "Action") }
    static var scope: String { t("Scope", "Portée") }
    static var domain: String { t("Domain", "Domaine") }
    static var any: String { t("Any", "Tout") }
    static var notes: String { t("Notes", "Notes") }
    static var optional: String { t("optional", "facultatif") }
    static var temporary1h: String { t("Temporary (1 hour)", "Temporaire (1 heure)") }
    static var processName: String { t("Process name", "Nom du processus") }
    static var bundleID: String { t("Bundle ID", "Bundle ID") }
    static var remoteHostIP: String { t("Remote host / IP", "Hôte distant / IP") }
    static var helperRuleQueued: String {
        t("Helper is offline. The rule is queued locally and synced when the helper connects.",
          "Le helper est hors ligne. La règle est mise en file localement et synchronisée à la connexion.")
    }
    static var anyProcess: String { t("Any process", "Tout processus") }
    static var anyHost: String { t("any host", "tout hôte") }
    static var direction: String { t("Direction", "Direction") }
    static var priority: String { t("Priority", "Priorité") }
    static var pathLabel: String { t("Path", "Chemin") }
    static func appFamilyStreams(_ count: Int) -> String {
        t("App family · \(count) streams", "Famille d’apps · \(count) flux")
    }
    static func destinationStreams(_ count: Int) -> String {
        t("\(count) streams", "\(count) flux")
    }
    static var suggestedFromFortress: String {
        t("Suggested from Fortress activity", "Suggestion depuis l’activité Fortress")
    }
    static var createdInFortressRules: String {
        t("Created in Fortress Rules", "Créée dans Règles Fortress")
    }
    static var processNameExample: String { t("e.g. Cursor", "ex. Cursor") }
    static var remoteHostExample: String { t("e.g. api.example.com", "ex. api.example.com") }
    static var openActivity: String { t("Open Activity…", "Ouvrir Activité…") }
    static var manageRules: String { t("Manage Rules…", "Gérer les règles…") }
    static var recentNetworkActivity: String {
        t("Recent Network Activity", "Activité réseau récente")
    }
    static var recentlyDenied: String { t("Recently Denied", "Récemment refusés") }
    static var mode: String { t("Mode", "Mode") }
    static var silentAllow: String { t("Silent Allow", "Autoriser en silence") }
    static var silentDeny: String { t("Silent Deny", "Refuser en silence") }
    static var alertMode: String { t("Alert", "Alerte") }
    static var tray: String { t("Tray", "Menu") }
    static var folder: String { t("Folder", "Dossier") }
    static var models: String { t("Models", "Modèles") }
    static var citadelSettings: String { t("Citadel Settings…", "Réglages Citadel…") }
    static var quitCitadel: String { t("Quit Citadel", "Quitter Citadel") }
    static var citadelCrest: String { t("Citadel Crest", "Citadel Crest") }
    static var quickOpen: String { t("Quick open", "Ouverture rapide") }
    static var roleMain: String { t("Main", "Principal") }
    static var roleHelpers: String { t("Helpers", "Helpers") }
    static var roleRenderer: String { t("Renderer", "Rendu") }
    static var roleGPU: String { t("GPU", "GPU") }
    static var roleNetwork: String { t("Network", "Réseau") }
    static var roleAgent: String { t("Agent", "Agent") }
    static var roleOther: String { t("Other", "Autre") }
    static func processCount(_ n: Int) -> String {
        t("\(n) process\(n == 1 ? "" : "es")", "\(n) processus")
    }
    static func streamCount(_ n: Int) -> String {
        t("\(n) stream\(n == 1 ? "" : "s")", "\(n) flux")
    }
    static func streamsViaHelpers(_ n: Int) -> String {
        t("\(n) stream\(n == 1 ? "" : "s") · via helpers",
          "\(n) flux · via helpers")
    }
    static func streamsWithHelpers(_ n: Int, _ helpers: Int) -> String {
        t("\(n) stream\(n == 1 ? "" : "s") · \(helpers) helper",
          "\(n) flux · \(helpers) helper")
    }
    static func remoteCount(_ n: Int) -> String {
        t("\(n) remote\(n == 1 ? "" : "s")", "\(n) distant\(n == 1 ? "" : "s")")
    }
    static var crestUnderNotch: String {
        t("Menubar icon is under the camera notch",
          "L’icône de la barre de menus est sous l’encoche caméra")
    }
    static var crestAtRisk: String {
        t("Tray is crowding the notch — Crest stays available",
          "Le menu est trop près de l’encoche — Crest reste disponible")
    }
    static var crestOverflow: String {
        t("Menu bar is full — Citadel was pushed out of the tray",
          "La barre de menus est pleine — Citadel a été poussé hors du menu")
    }
    static var crestMissing: String { t("Menubar icon unavailable", "Icône de la barre de menus indisponible") }
    static var crestHoverNotch: String {
        t("Hover the notch anytime for Citadel",
          "Survolez l’encoche à tout moment pour Citadel")
    }
    static var crestTopCenter: String {
        t("Top-center recover when the tray gets crowded",
          "Récupération en haut au centre quand le menu est saturé")
    }
    static var outbound: String { t("Outbound", "Sortant") }
    static var inbound: String { t("Inbound", "Entrant") }
    static var denied: String { t("Denied", "Refusé") }
    static var mapZoomHint: String {
        t("Scroll or pinch to zoom · drag to pan",
          "Molette ou pincement pour zoomer · glisser pour déplacer")
    }
    static var mapRotateHint: String {
        t("Drag to rotate · scroll to zoom",
          "Glisser pour tourner · molette pour zoomer")
    }
    static var mapFrozenHint: String {
        t("Auto-spin frozen · drag to rotate · scroll to zoom",
          "Rotation auto gelée · glisser pour tourner · molette pour zoomer")
    }
    static var freezeRotation: String {
        t("Freeze auto-rotation (drag still works)",
          "Geler la rotation auto (le glisser fonctionne encore)")
    }
    static var resumeRotation: String { t("Resume auto-rotation", "Reprendre la rotation auto") }
    static var noPublicDestinations: String {
        t("No public destinations to plot", "Aucune destination publique à afficher")
    }
    static var privateVPNMapHint: String {
        t("Private and VPN tunnel IPs can’t be placed on the map. Select All or an app with internet remotes — or Load demo.",
          "Les IP privées et tunnels VPN ne peuvent pas être placées sur la carte. Sélectionnez Tout ou une app avec des destinations internet — ou chargez la démo.")
    }
    static func activeFlows(_ n: Int) -> String {
        t("\(n) active flows", "\(n) flux actifs")
    }
    static var rememberDecision: String {
        t("Remember this decision", "Mémoriser cette décision")
    }
    static var duration: String { t("Duration", "Durée") }

    // MARK: - Settings

    static var settingsGeneral: String { t("General", "Général") }
    static var settingsDNS: String { t("DNS", "DNS") }
    static var settingsBlocklists: String { t("Blocklists", "Listes de blocage") }
    static var settingsProfiles: String { t("Profiles", "Profils") }
    static var settingsAbout: String { t("About", "À propos") }
    static var launchAtLogin: String { t("Launch Citadel at login", "Lancer Citadel à la connexion") }
    static var showAlertsAllSpaces: String {
        t("Show alerts on all Spaces", "Afficher les alertes sur tous les espaces")
    }
    static var defaultMode: String { t("Default mode", "Mode par défaut") }
    static var appearance: String { t("Appearance", "Apparence") }
    static var fontSize: String { t("Font size", "Taille du texte") }
    static var reset: String { t("Reset", "Réinitialiser") }
    static var fontScaleHint: String {
        t("Scales text across all Citadel windows.", "Ajuste le texte dans toutes les fenêtres Citadel.")
    }
    static var menuBar: String { t("Menu bar", "Barre de menus") }
    static var crestMenuBarHint: String {
        t("When the menu bar crowds the notch, Citadel hides its tray icon so it won’t push other apps under the camera. Hover the notch anytime for Crest (Tray, Activity, Rules, Settings). The tray icon only comes back after a display change if there is room.",
          "Quand la barre de menus est trop près de l’encoche, Citadel masque son icône pour ne pas pousser d’autres apps sous la caméra. Survolez l’encoche pour Crest (Menu, Activité, Règles, Réglages). L’icône ne revient qu’après un changement d’écran s’il y a de la place.")
    }
    static var crestPinnedAppsHint: String {
        t("Optional pinned apps: defaults write com.citadel.firewall citadel.crest.pinnedBundleIDs -array-add \"com.example.app\"",
          "Apps épinglées (optionnel) : defaults write com.citadel.firewall citadel.crest.pinnedBundleIDs -array-add \"com.example.app\"")
    }
    static var dohUpstream: String { t("DNS over HTTPS upstream", "Serveur DNS over HTTPS") }
    static var dohURL: String { t("DoH URL", "URL DoH") }
    static var examples: String { t("Examples:", "Exemples :") }
    static var localDNSProxy: String { t("Local DNS proxy", "Proxy DNS local") }
    static var useSystemDNS: String {
        t("Use system DNS via Citadel (port 53)", "Utiliser le DNS système via Citadel (port 53)")
    }
    static var localDNSHint: String {
        t("Citadel installs itself as the system DNS resolver to intercept and filter domain lookups.",
          "Citadel s’installe comme résolveur DNS système pour intercepter et filtrer les requêtes.")
    }
    static var refreshAll: String { t("Refresh All", "Tout actualiser") }
    static var active: String { t("Active", "Actif") }
    static var activate: String { t("Activate", "Activer") }
    static var aboutTagline: String {
        t("Fortress watches the network. Keep runs your agents — local or cloud — inside the walls.",
          "Fortress surveille le réseau. Keep fait tourner vos agents — locaux ou cloud — à l’intérieur des murs.")
    }
    static var aboutAttributions: String {
        t("Open-source attributions are listed in ATTRIBUTIONS.md and NOTICES.md.",
          "Les attributions open source sont listées dans ATTRIBUTIONS.md et NOTICES.md.")
    }
    static var fiveMinutesAgo: String { t("5 minutes ago", "Il y a 5 minutes") }
    static var now: String { t("now", "maintenant") }

    /// User-facing status line (localized errors + hints).
    static func statusLine(
        _ raw: String?,
        chatOnly: Bool = false,
        providerPlatform: String? = nil,
        mcpCount: Int = 0
    ) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if chatOnly {
            let lower = raw.lowercased()
            if lower.contains("provider rejected")
                || lower.contains("rejected the request")
                || lower.contains("tool schema")
                || lower.contains("invalid tool")
                || lower.contains("model provider rejected") {
                return nil
            }
        }
        let localized = localizeError(raw, providerPlatform: providerPlatform)
        let rejected = providerRejectedError(platform: providerPlatform)
        if localized == rejected, !chatOnly {
            var line = localized + "\n" + providerRejectedHint(platform: providerPlatform, mcpCount: mcpCount)
            if !raw.lowercased().contains(localized.lowercased()) {
                line += "\n" + raw
            }
            return line
        }
        if localized == rejected, chatOnly {
            return nil
        }
        return localized
    }
}
