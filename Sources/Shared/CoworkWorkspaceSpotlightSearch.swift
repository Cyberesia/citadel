import Foundation

/// Finder / Spotlight content search scoped to a workspace folder (`kMDItemTextContent`).
enum CoworkWorkspaceSpotlightSearch {
    private static let searchTimeout: TimeInterval = 2.5

    /// Paths under `workspace` whose indexed text matches any search token.
    static func matchingPaths(in workspace: String, tokens: [String]) -> [String] {
        let scoped = tokens.filter { $0.count >= 3 }
        guard !scoped.isEmpty else { return [] }

        let workspaceURL = URL(fileURLWithPath: workspace)
        let query = NSMetadataQuery()
        let predicates = scoped.map { NSPredicate(format: "kMDItemTextContent CONTAINS[cd] %@", $0) }
        query.predicate = predicates.count == 1
            ? predicates[0]
            : NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        query.searchScopes = [workspaceURL]

        final class GatherState: @unchecked Sendable {
            var finished = false
        }
        let state = GatherState()
        let observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: nil
        ) { _ in
            state.finished = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        guard query.start() else { return [] }

        let deadline = Date().addingTimeInterval(searchTimeout)
        while !state.finished && query.isGathering && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        query.stop()

        let prefix = workspace.hasSuffix("/") ? workspace : workspace + "/"
        return (query.results as? [NSMetadataItem] ?? []).compactMap { item in
            item.value(forAttribute: "kMDItemPath") as? String
        }
        .filter { $0 == workspace || $0.hasPrefix(prefix) }
        .filter { CoworkIndexableDocumentTypes.isIndexable(path: $0) }
    }
}
