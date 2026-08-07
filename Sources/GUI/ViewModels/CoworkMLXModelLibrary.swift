import Foundation
import Combine

enum CoworkMLXDownloadState: Sendable, Equatable {
    case idle
    case downloading
    case paused
}

@MainActor
final class CoworkMLXModelLibrary: ObservableObject {
    static let shared = CoworkMLXModelLibrary()

    @Published private(set) var installedByteSizes: [String: Int64] = [:]
    @Published private(set) var partialByteSizes: [String: Int64] = [:]
    @Published private(set) var downloadError: String?
    @Published var activeDownloadRepoID: String?
    @Published private(set) var activeDownloadState: CoworkMLXDownloadState = .idle
    @Published private(set) var downloadFraction: Double = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64 = 0

    private var downloader: CoworkMLXKleeModelDownloader?
    private var downloadTask: Task<Void, Never>?

    func refreshInstalledByteSizes() {
        Task { await refreshInstalledByteSizesAsync() }
    }

    func refreshInstalledByteSizesAsync() async {
        var complete: [String: Int64] = [:]
        var partial: [String: Int64] = [:]
        for model in CoworkMLXModelCatalog.models {
            if let dir = await CoworkMLXHubSnapshot.localSnapshotDirectory(repoID: model.id) {
                complete[model.id] = CoworkMLXHubSnapshot.directoryAllocatedBytes(at: dir)
            } else if let loose = CoworkMLXHubSnapshot.largestLocalSnapshotAnyState(repoID: model.id) {
                partial[model.id] = loose.bytes
            }
        }
        installedByteSizes = complete
        partialByteSizes = partial
    }

    func installedModels() -> [CoworkMLXModelInfo] {
        CoworkMLXModelCatalog.models.filter { (installedByteSizes[$0.id] ?? 0) > 0 }
    }

    static func enrichedLoadErrorMessage(_ raw: String) -> String {
        let lower = raw.lowercased()
        let looksLikeMissingWeights =
            lower.contains("lm_head")
            || (lower.contains("key ") && lower.contains("not found"))
            || lower.contains("not found in ")
            || lower.contains("weight not found")
        guard looksLikeMissingWeights else { return raw }
        let hint = L10n.mlxIncompleteDownloadHint
        return raw + "\n\n" + hint
    }

    func startDownload(repoID: String) {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        downloadError = nil
        activeDownloadRepoID = trimmed
        activeDownloadState = .downloading
        downloadFraction = 0
        downloadedBytes = 0
        expectedBytes = CoworkMLXModelCatalog.models.first { $0.id == trimmed }?.expectedDownloadBytes ?? 0

        downloadTask?.cancel()
        let dl = CoworkMLXKleeModelDownloader()
        downloader = dl
        dl.onProgress = { [weak self] done, total, _ in
            guard let self else { return }
            self.downloadedBytes = done
            self.expectedBytes = total
            self.downloadFraction = total > 0 ? Double(done) / Double(total) : 0
        }

        downloadTask = Task {
            do {
                _ = try await dl.downloadModel(repoID: trimmed)
                self.activeDownloadRepoID = nil
                self.activeDownloadState = .idle
                self.downloadFraction = 1
                await self.refreshInstalledByteSizesAsync()
            } catch is CancellationError {
                self.activeDownloadRepoID = nil
                self.activeDownloadState = .idle
            } catch {
                self.activeDownloadRepoID = nil
                self.activeDownloadState = .idle
                self.downloadError = error.localizedDescription
            }
        }
    }

    func cancelDownload() {
        downloader?.cancel()
        downloadTask?.cancel()
        downloadTask = nil
        downloader = nil
        activeDownloadRepoID = nil
        activeDownloadState = .idle
    }

    func deleteCache(repoID: String) throws {
        if activeDownloadRepoID == repoID { cancelDownload() }
        try CoworkMLXHubCache.removeAllCacheData(forRepoID: repoID)
        installedByteSizes[repoID] = nil
        partialByteSizes[repoID] = nil
    }
}
