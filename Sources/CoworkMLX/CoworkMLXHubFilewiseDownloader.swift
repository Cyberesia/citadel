import Darwin
import Foundation
import HuggingFace
import MLXLMCommon

struct CoworkMLXHubFilewiseDownloader: Downloader {
    private let hub = HubClient()

    enum DownloadError: LocalizedError {
        case invalidRepositoryID(String)
        case incompleteSnapshot(String)

        var errorDescription: String? {
            switch self {
            case .invalidRepositoryID(let id):
                return "Invalid Hugging Face repository ID: '\(id)'. Expected format 'namespace/name'."
            case .incompleteSnapshot(let id):
                return "Model '\(id)' is not fully downloaded. Some required files are missing or have the wrong size."
            }
        }
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw DownloadError.invalidRepositoryID(id)
        }

        let rev = revision ?? "main"

        if !useLatest,
           let cached = try? await hub.downloadSnapshot(
                of: repoID,
                revision: rev,
                matching: patterns,
                localFilesOnly: true,
                progressHandler: { progressHandler($0) }
           ) {
            return cached
        }

        let activePatterns = patterns.isEmpty ? CoworkMLXHubSnapshot.modelFilePatterns : patterns
        var entries = try await hub.listFiles(in: repoID, revision: rev)
            .filter { entry in
                activePatterns.contains { fnmatch($0, entry.path, 0) == 0 }
            }
        entries.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let totalBytes: Int64 = max(
            entries.reduce(Int64(0)) { acc, e in acc + max(Int64(e.size ?? 1), 1) },
            1
        )
        let overall = Progress(totalUnitCount: totalBytes)
        updateDiskBackedProgress(overall, repoID: id, totalBytes: totalBytes, progressHandler: progressHandler)
        progressHandler(overall)

        let diskPoll = Task { @Sendable in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                updateDiskBackedProgress(
                    overall,
                    repoID: id,
                    totalBytes: totalBytes,
                    progressHandler: progressHandler
                )
            }
        }
        defer { diskPoll.cancel() }

        for entry in entries {
            try Task.checkCancellation()

            let fileTotal = max(Int64(entry.size ?? 1), 1)
            let perFile = Progress(totalUnitCount: fileTotal)

            _ = try await hub.downloadFile(
                entry,
                from: repoID,
                revision: rev,
                progress: perFile,
                transport: .lfs
            )

            updateDiskBackedProgress(overall, repoID: id, totalBytes: totalBytes, progressHandler: progressHandler)
        }

        let snapshot = try await hub.downloadSnapshot(
            of: repoID,
            revision: rev,
            matching: activePatterns,
            localFilesOnly: true
        )
        guard await CoworkMLXHubSnapshot.snapshotMatchesHubManifest(
            at: snapshot,
            repo: repoID,
            revision: rev
        ) else {
            throw DownloadError.incompleteSnapshot(id)
        }
        return snapshot
    }

    private func updateDiskBackedProgress(
        _ progress: Progress,
        repoID: String,
        totalBytes: Int64,
        progressHandler: @Sendable (Progress) -> Void
    ) {
        let bytesOnDisk = CoworkMLXHubSnapshot.hubCacheStoredBytes(forRepoID: repoID)
        progress.completedUnitCount = min(max(bytesOnDisk, 0), totalBytes)
        progressHandler(progress)
    }
}
