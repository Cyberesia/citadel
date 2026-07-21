import Foundation

/// A hard, explainable suspicious-communication finding.
struct SuspectFinding: Identifiable, Hashable, Sendable {
    let id: String
    let streamID: String
    let severity: SuspectSeverity
    let title: [String: String]
    let reasons: [[String: String]]
    let processName: String
    let familyName: String
    let remoteLabel: String
    let remotePort: Int
    let codeTeamID: String?
    let signingStatus: ProcessSigningStatus
    let signalKeys: [String]
    let createdAt: Date

    func resolvedTitle(locale: CitadelLocale = .current) -> String {
        Self.resolve(title, locale: locale)
    }

    func resolvedReasons(locale: CitadelLocale = .current) -> [String] {
        reasons.map { Self.resolve($0, locale: locale) }
    }

    private static func resolve(_ map: [String: String], locale: CitadelLocale) -> String {
        if let s = map[locale.rawValue], !s.isEmpty { return s }
        if let s = map["en"], !s.isEmpty { return s }
        return map.values.first ?? ""
    }
}

enum SuspectSeverity: String, Codable, Sendable, Hashable {
    case info
    case watch
    case alert
}

/// Evaluates live streams against hard local signals (no cloud reputation).
struct SuspectEngine: Sendable {
    static let sensitivePorts: Set<Int> = [
        22, 23, 135, 139, 445, 1433, 1521, 3306, 3389, 5432, 5900, 6379, 27017
    ]

    init() {}

    func evaluate(
        streams: [NetworkStream],
        rules: [Rule],
        store: RuleStore?,
        blocklistDomains: Set<String> = [],
        now: Date = Date()
    ) -> [SuspectFinding] {
        let knownTeams = store?.knownTeamIDs() ?? []
        let allowRules = rules.filter { $0.enabled && $0.action == .allow }
        let evaluator = FirewallRuleEvaluator()

        // Family rate baseline for spike detection
        var familyRates: [String: [Int64]] = [:]
        for s in streams {
            familyRates[s.process.familyID, default: []].append(s.rateTotal)
        }

        var findings: [SuspectFinding] = []
        var seenIDs = Set<String>()

        for stream in streams {
            var signals: [(String, SuspectSeverity, [String: String])] = []

            // Sightings (first-seen)
            let processKey = stream.process.bundleID ?? stream.process.path
            let hostKey = stream.remoteKey
            let firstProcess = store.map { !$0.hasSighting(kind: "process", key: processKey) } ?? false
            let firstHost = store.map { !$0.hasSighting(kind: "host", key: hostKey) } ?? false
            _ = store?.recordSighting(kind: "process", key: processKey, at: now)
            _ = store?.recordSighting(kind: "host", key: hostKey, at: now)

            switch stream.process.signingStatus {
            case .unsigned:
                signals.append(("unsigned", .alert, [
                    "en": "This app is not code-signed.",
                    "fr": "Cette app n’est pas signée numériquement."
                ]))
            case .signedInvalid:
                signals.append(("bad-sign", .alert, [
                    "en": "This app’s signature is invalid.",
                    "fr": "La signature de cette app est invalide."
                ]))
            case .signedValid, .unknown:
                break
            }

            if stream.process.signingStatus == .signedValid {
                if let team = stream.process.codeTeamID, !team.isEmpty, !knownTeams.contains(team) {
                    // Only flag unknown team when first-seen process — avoid noise
                    if firstProcess {
                        signals.append(("unknown-team", .watch, [
                            "en": "Developer Team ID \(team) has never been allowed before.",
                            "fr": "Le Team ID développeur \(team) n’a jamais été autorisé."
                        ]))
                    }
                }
            } else if stream.process.codeTeamID == nil, stream.process.signingStatus != .unknown {
                signals.append(("no-team", .watch, [
                    "en": "No Apple Developer Team ID could be verified.",
                    "fr": "Aucun Team ID développeur Apple n’a pu être vérifié."
                ]))
            }

            if firstProcess {
                signals.append(("first-process", .watch, [
                    "en": "First time Fortress sees this app on your Mac.",
                    "fr": "Première fois que Fortress voit cette app sur votre Mac."
                ]))
            }
            if firstHost {
                signals.append(("first-host", .watch, [
                    "en": "First time this destination is contacted.",
                    "fr": "Première fois que cette destination est contactée."
                ]))
            }

            let domain = stream.remoteDisplayName.lowercased()
            if !domain.isEmpty, blocklistHit(domain, in: blocklistDomains) {
                signals.append(("blocklist", .alert, [
                    "en": "Destination matches an enabled DNS blocklist.",
                    "fr": "La destination figure dans une blocklist DNS active."
                ]))
            }

            let asConnection = Connection(
                pid: stream.process.pid,
                processName: stream.process.name,
                processPath: stream.process.path,
                processBundleId: stream.process.bundleID,
                codeTeamID: stream.process.codeTeamID,
                signingStatus: stream.process.signingStatus,
                remoteHost: stream.remoteHost,
                remoteIP: stream.remoteIP,
                remotePort: stream.remotePort,
                status: .established
            )
            let hasAllow = allowRules.contains { evaluator.matches(rule: $0, connection: asConnection) }
            if !hasAllow {
                signals.append(("never-allowed", .info, [
                    "en": "You have never allowed this connection with a rule.",
                    "fr": "Vous n’avez jamais autorisé cette connexion par une règle."
                ]))
            }

            if [.helper, .agent, .network].contains(stream.process.role), firstHost {
                signals.append(("helper-new-host", .watch, [
                    "en": "A background helper is contacting a new server.",
                    "fr": "Un processus d’arrière-plan contacte un nouveau serveur."
                ]))
            }

            if Self.sensitivePorts.contains(stream.remotePort),
               !isBrowserLike(stream.process.familyName) {
                signals.append(("sensitive-port", .alert, [
                    "en": "Unusual port \(stream.remotePort) for a consumer app.",
                    "fr": "Port inhabituel \(stream.remotePort) pour une app grand public."
                ]))
            }

            let rates = familyRates[stream.process.familyID] ?? []
            if let median = median(rates), median > 0, stream.rateTotal > median * 8, stream.rateTotal > 50_000 {
                signals.append(("volume-spike", .watch, [
                    "en": "Traffic spike vs this app’s recent baseline.",
                    "fr": "Pic de trafic par rapport à la normale récente de cette app."
                ]))
            }

            guard !signals.isEmpty else { continue }

            // Require at least one watch/alert OR (first-process + never-allowed) to list
            let hasStrong = signals.contains { $0.1 == .alert || $0.1 == .watch }
            let softOnly = !hasStrong && signals.allSatisfy { $0.0 == "never-allowed" }
            if softOnly { continue }

            let severity = signals.map(\.1).max(by: { rank($0) < rank($1) }) ?? .info
            let id = "\(stream.process.familyID)|\(stream.remoteKey)|\(signals.map(\.0).sorted().joined(separator: ","))"
            if seenIDs.contains(id) { continue }
            seenIDs.insert(id)

            let title = humanTitle(signals: signals.map(\.0), process: stream.process.familyName, host: stream.remoteDisplayName)
            findings.append(SuspectFinding(
                id: id,
                streamID: stream.id,
                severity: severity,
                title: title,
                reasons: signals.map(\.2),
                processName: stream.process.name,
                familyName: stream.process.familyName,
                remoteLabel: stream.remoteDisplayName,
                remotePort: stream.remotePort,
                codeTeamID: stream.process.codeTeamID,
                signingStatus: stream.process.signingStatus,
                signalKeys: signals.map(\.0),
                createdAt: now
            ))
        }

        return findings.sorted {
            if rank($0.severity) != rank($1.severity) {
                return rank($0.severity) > rank($1.severity)
            }
            return $0.familyName < $1.familyName
        }
    }

    private func rank(_ s: SuspectSeverity) -> Int {
        switch s {
        case .alert: return 3
        case .watch: return 2
        case .info: return 1
        }
    }

    private func blocklistHit(_ domain: String, in list: Set<String>) -> Bool {
        if list.contains(domain) { return true }
        var parts = domain.split(separator: ".")
        while parts.count > 1 {
            parts.removeFirst()
            if list.contains(parts.joined(separator: ".")) { return true }
        }
        return false
    }

    private func isBrowserLike(_ family: String) -> Bool {
        let n = family.lowercased()
        return ["safari", "chrome", "firefox", "edge", "brave", "arc", "opera"].contains { n.contains($0) }
    }

    private func median(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func humanTitle(signals: [String], process: String, host: String) -> [String: String] {
        if signals.contains("unsigned") || signals.contains("bad-sign") {
            return [
                "en": "\(process) is unsigned and contacting \(host)",
                "fr": "\(process) n’est pas signée et contacte \(host)"
            ]
        }
        if signals.contains("blocklist") {
            return [
                "en": "\(process) reached a blocked destination (\(host))",
                "fr": "\(process) a contacté une destination bloquée (\(host))"
            ]
        }
        if signals.contains("sensitive-port") {
            return [
                "en": "\(process) used a sensitive network port to \(host)",
                "fr": "\(process) a utilisé un port réseau sensible vers \(host)"
            ]
        }
        if signals.contains("helper-new-host") {
            return [
                "en": "A background part of \(process) contacted a new server",
                "fr": "Une partie d’arrière-plan de \(process) a contacté un nouveau serveur"
            ]
        }
        if signals.contains("first-process") || signals.contains("first-host") {
            return [
                "en": "New activity: \(process) → \(host)",
                "fr": "Nouvelle activité : \(process) → \(host)"
            ]
        }
        return [
            "en": "Review: \(process) → \(host)",
            "fr": "À vérifier : \(process) → \(host)"
        ]
    }
}
