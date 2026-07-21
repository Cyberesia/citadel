import Foundation

enum CoworkMLXHubCache {
    static func citadelCacheDirectory(forRepoID repoID: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Citadel/MLXModels", isDirectory: true)
            .appendingPathComponent(repoID, isDirectory: true)
    }

    static func hubRepoFolderName(repoID: String) -> String {
        "models--" + repoID.replacingOccurrences(of: "/", with: "--")
    }

    static func hubCacheRoots() -> [URL] {
        var roots: [URL] = []
        func add(_ url: URL) {
            let s = url.standardizedFileURL
            if roots.contains(where: { $0.standardizedFileURL == s }) { return }
            roots.append(s)
        }
        if let raw = ProcessInfo.processInfo.environment["HF_HUB_CACHE"], !raw.isEmpty {
            add(URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true))
        }
        add(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
        )
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            add(caches.appendingPathComponent("huggingface/hub", isDirectory: true))
        }
        return roots
    }

    static func localModelPath(forRepoID repoID: String) -> String? {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let citadel = citadelCacheDirectory(forRepoID: trimmed)
        if directoryHasWeights(at: citadel) { return citadel.path }

        let folder = hubRepoFolderName(repoID: trimmed)
        let fm = FileManager.default
        var bestURL: URL?
        var bestBytes: Int64 = 0
        for root in hubCacheRoots() {
            let snapRoot = root.appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true)
            guard fm.fileExists(atPath: snapRoot.path),
                  let commits = try? fm.contentsOfDirectory(
                    at: snapRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                  ) else { continue }
            for commitURL in commits {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: commitURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
                guard directoryHasWeights(at: commitURL) else { continue }
                let bytes = directoryAllocatedBytes(at: commitURL)
                if bytes > bestBytes {
                    bestBytes = bytes
                    bestURL = commitURL
                }
            }
        }
        return bestURL?.path
    }

    static func isRepoComplete(_ repoID: String) -> Bool {
        localModelPath(forRepoID: repoID) != nil
    }

    static func partialBytes(forRepoID repoID: String) -> Int64 {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let citadel = citadelCacheDirectory(forRepoID: trimmed)
        let fm = FileManager.default
        if fm.fileExists(atPath: citadel.path) {
            let bytes = directoryAllocatedBytes(at: citadel)
            if bytes > 0, !directoryHasWeights(at: citadel) { return bytes }
        }
        let folder = hubRepoFolderName(repoID: trimmed)
        var best: Int64 = 0
        for root in hubCacheRoots() {
            let snapRoot = root.appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true)
            guard let commits = try? fm.contentsOfDirectory(at: snapRoot, includingPropertiesForKeys: nil) else { continue }
            for commitURL in commits {
                let bytes = directoryAllocatedBytes(at: commitURL)
                if bytes > best { best = bytes }
            }
        }
        return best
    }

    static func installedBytes(forRepoID repoID: String) -> Int64 {
        guard let path = localModelPath(forRepoID: repoID) else { return 0 }
        return directoryAllocatedBytes(at: URL(fileURLWithPath: path))
    }

    static func removeAllCacheData(forRepoID repoID: String) throws {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fm = FileManager.default
        let folder = hubRepoFolderName(repoID: trimmed)
        for root in hubCacheRoots() {
            let repoRoot = root.appendingPathComponent(folder, isDirectory: true)
            if fm.fileExists(atPath: repoRoot.path) {
                try fm.removeItem(at: repoRoot)
            }
        }
        let citadel = citadelCacheDirectory(forRepoID: trimmed)
        if fm.fileExists(atPath: citadel.path) {
            try fm.removeItem(at: citadel)
        }
    }

    static func directoryHasWeights(at url: URL) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return false }
        for case let file as URL in enumerator {
            guard file.pathExtension.lowercased() == "safetensors" else { continue }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 1_000_000 { return true }
        }
        return false
    }

    static func directoryAllocatedBytes(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
