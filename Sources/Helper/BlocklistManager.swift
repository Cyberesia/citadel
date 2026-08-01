import Foundation

/// Fetches enabled remote blocklists and publishes a merged domain set for DNS filtering.
final class BlocklistManager: @unchecked Sendable {
    private let store: RuleStore
    private let fetchSession: URLSession
    private let stateLock = NSLock()
    private var cachedDomains: Set<String> = []

    var onUpdate: ((Int) -> Void)?

    var domains: Set<String> {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedDomains
    }

    init(store: RuleStore) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        fetchSession = URLSession(configuration: config)
    }

    func refresh() async {
        let enabledLists = store.allBlocklists().filter(\.enabled)
        var merged = Set<String>()

        await withTaskGroup(of: (BlocklistInfo, Set<String>).self) { group in
            for list in enabledLists {
                group.addTask { [fetchSession] in
                    let domains = await Self.downloadDomains(for: list, session: fetchSession)
                    return (list, domains)
                }
            }

            for await (list, downloaded) in group {
                merged.formUnion(downloaded)
                persistMetadata(for: list, entryCount: downloaded.count)
            }
        }

        stateLock.lock()
        cachedDomains = merged
        stateLock.unlock()

        onUpdate?(merged.count)
    }

    // MARK: - Fetch

    private static func downloadDomains(for list: BlocklistInfo, session: URLSession) async -> Set<String> {
        guard let url = URL(string: list.url) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Citadel/\(AppConstants.version)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await session.data(for: request)
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return BlocklistFeedParser.domains(from: text)
        } catch {
            CitadelLog.error(CitadelLog.dns, "Blocklist download failed (\(list.name)): \(error.localizedDescription)")
            return []
        }
    }

    private func persistMetadata(for list: BlocklistInfo, entryCount: Int) {
        var updated = list
        updated.entryCount = entryCount
        updated.lastUpdated = Date()
        try? store.updateBlocklist(updated)
    }
}
