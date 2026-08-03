import Darwin
import Foundation
import HuggingFace

enum CoworkMLXHubSnapshot {
    static let modelFilePatterns = ["*.safetensors", "*.json", "*.jinja"]

    static func localSnapshotDirectory(repoID: String, revision: String = "main") async -> URL? {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rid = Repo.ID(rawValue: trimmed) else { return nil }
        let citadelDir = CoworkMLXHubCache.citadelCacheDirectory(forRepoID: trimmed)
        if await localDirectoryMatchesHubManifest(at: citadelDir, repoID: trimmed) {
            return citadelDir
        }
        let client = HubClient()
        if let url = try? await client.downloadSnapshot(
            of: rid,
            kind: .model,
            revision: revision,
            matching: [],
            localFilesOnly: true,
            progressHandler: nil
        ), await snapshotMatchesHubManifest(at: url, repo: rid, revision: revision) {
            return url
        }
        return await bestCompleteSnapshotInHubCaches(repo: rid, revision: revision)
    }

    /// Largest on-disk snapshot even if incomplete (for partial-download UI).
    static func largestLocalSnapshotAnyState(repoID: String) -> (url: URL, bytes: Int64)? {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rid = Repo.ID(rawValue: trimmed) else { return nil }
        let fm = FileManager.default
        var bestURL: URL?
        var bestBytes: Int64 = 0
        for dir in [
            CoworkMLXHubCache.citadelCacheDirectory(forRepoID: trimmed),
        ] {
            guard fm.fileExists(atPath: dir.path) else { continue }
            let bytes = directoryStoredBytes(at: dir)
            if bytes > bestBytes {
                bestBytes = bytes
                bestURL = dir
            }
        }
        let repoFolder = hubRepoFolderName(repo: rid)
        for root in hubCacheRootsDistinct() {
            let snapRoot = root.appendingPathComponent(repoFolder, isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true)
            guard let commits = try? fm.contentsOfDirectory(
                at: snapRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for commitURL in commits {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: commitURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let bytes = CoworkMLXHubCache.directoryAllocatedBytes(at: commitURL)
                if bytes > bestBytes {
                    bestBytes = bytes
                    bestURL = commitURL
                }
            }
        }
        guard let bestURL, bestBytes > 0 else { return nil }
        return (bestURL, bestBytes)
    }

    static func directoryAllocatedBytes(at root: URL) -> Int64 {
        directoryStoredBytes(at: root)
    }

    static func hubCacheStoredBytes(forRepoID repoID: String) -> Int64 {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rid = Repo.ID(rawValue: trimmed) else { return 0 }
        let fm = FileManager.default
        let folder = hubRepoFolderName(repo: rid)
        var total: Int64 = 0
        for root in hubCacheRootsDistinct() {
            let repoRoot = root.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: repoRoot.path) else { continue }
            total += directoryStoredBytes(at: repoRoot)
        }
        let citadelDir = CoworkMLXHubCache.citadelCacheDirectory(forRepoID: trimmed)
        if fm.fileExists(atPath: citadelDir.path) {
            total += directoryStoredBytes(at: citadelDir)
        }
        return total
    }

    static func snapshotMatchesHubManifest(
        at directory: URL,
        repo: Repo.ID,
        revision: String = "main"
    ) async -> Bool {
        let client = HubClient()
        guard let entries = try? await client.listFiles(in: repo, revision: revision) else {
            return snapshotLooksLocallyUsable(at: directory)
        }
        let required = entries.filter { entry in
            modelFilePatterns.contains { fnmatch($0, entry.path, 0) == 0 }
        }
        guard required.contains(where: { $0.path.hasSuffix(".safetensors") }) else { return false }

        for entry in required {
            let local = directory.appendingPathComponent(entry.path)
            guard localFile(at: local, matchesExpectedSize: entry.size) else {
                return false
            }
        }
        return true
    }

    static func localDirectoryMatchesHubManifest(at directory: URL, repoID: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path), let rid = Repo.ID(rawValue: repoID) else {
            return false
        }
        return await snapshotMatchesHubManifest(at: directory, repo: rid)
    }

    static func snapshotLooksLocallyUsable(at directory: URL) -> Bool {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        var safetensorBytes: Int64 = 0
        for case let url as URL in en {
            guard url.lastPathComponent.lowercased().hasSuffix(".safetensors") else { continue }
            let resolved = url.resolvingSymlinksInPath()
            guard fm.fileExists(atPath: resolved.path) else { continue }
            let size = (try? fm.attributesOfItem(atPath: resolved.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 1_000_000, !looksLikeGitLFSPointer(at: resolved) else { continue }
            safetensorBytes += size
        }
        return safetensorBytes > 100_000_000
    }

    static func directoryStoredBytes(at root: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]) else {
                continue
            }
            if values.isDirectory == true || values.isSymbolicLink == true {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func hubRepoFolderName(repo: Repo.ID) -> String {
        "models--" + repo.description.replacingOccurrences(of: "/", with: "--")
    }

    private static func bestCompleteSnapshotInHubCaches(repo: Repo.ID, revision: String) async -> URL? {
        let fm = FileManager.default
        let repoFolder = hubRepoFolderName(repo: repo)
        var bestURL: URL?
        var bestBytes: Int64 = 0
        for root in hubCacheRootsDistinct() {
            let snapRoot = root.appendingPathComponent(repoFolder, isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true)
            guard fm.fileExists(atPath: snapRoot.path) else { continue }
            guard let commits = try? fm.contentsOfDirectory(
                at: snapRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for commitURL in commits {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: commitURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
                guard await snapshotMatchesHubManifest(at: commitURL, repo: repo, revision: revision) else { continue }
                let bytes = CoworkMLXHubCache.directoryAllocatedBytes(at: commitURL)
                if bytes > bestBytes {
                    bestBytes = bytes
                    bestURL = commitURL
                }
            }
        }
        return bestURL
    }

    private static func hubCacheRootsDistinct() -> [URL] {
        var roots: [URL] = []
        func add(_ url: URL) {
            let s = url.standardizedFileURL
            if roots.contains(where: { $0.standardizedFileURL == s }) { return }
            roots.append(s)
        }
        add(HubCache.default.cacheDirectory)
        for root in CoworkMLXHubCache.hubCacheRoots() {
            add(root)
        }
        return roots
    }

    private static func localFile(at url: URL, matchesExpectedSize expected: Int?) -> Bool {
        let fm = FileManager.default
        let resolved = url.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: resolved.path) else { return false }
        let size = (try? fm.attributesOfItem(atPath: resolved.path)[.size] as? NSNumber)?.int64Value ?? -1
        guard size > 0 else { return false }
        if url.lastPathComponent.lowercased().hasSuffix(".safetensors") {
            guard size > 1_000_000, !looksLikeGitLFSPointer(at: resolved) else { return false }
        }
        if let expected {
            return size == Int64(expected)
        }
        return true
    }

    private static func looksLikeGitLFSPointer(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 128)
        guard let prefix = String(data: data, encoding: .utf8) else { return false }
        return prefix.hasPrefix("version https://git-lfs.github.com/spec/v1")
    }
}
