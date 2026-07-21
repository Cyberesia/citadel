import Foundation

final class CoworkMLXKleeModelDownloader: @unchecked Sendable {
    private let fileDownloader = CoworkMLXKleeFileDownloader()

    var onProgress: CoworkMLXKleeDownloadProgressCallback? {
        get { fileDownloader.onProgress }
        set { fileDownloader.onProgress = newValue }
    }

    func cancel() {
        fileDownloader.cancelActiveTask()
    }

    func pause() {
        fileDownloader.pauseActiveTask()
    }

    func downloadModel(repoID: String) async throws -> URL {
        let localDir = CoworkMLXHubCache.citadelCacheDirectory(forRepoID: repoID)
        let files = try await CoworkMLXKleeHuggingFaceAPI.fetchFileList(modelID: repoID)
        let filtered = CoworkMLXKleeHuggingFaceAPI.filterFiles(files)
        guard !filtered.isEmpty else {
            throw CoworkMLXKleeDownloadError.failed("No downloadable files found for \(repoID)")
        }

        let totalBytes = filtered.reduce(Int64(0)) { $0 + max($1.size ?? 0, 0) }
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)

        var downloadedBytes: Int64 = 0
        for file in filtered {
            try Task.checkCancellation()
            let fileURL = localDir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let expectedSize = file.size ?? 0
            if expectedSize > 0,
               let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let existingSize = attrs[.size] as? Int64,
               existingSize == expectedSize {
                downloadedBytes += expectedSize
                await onProgress?(downloadedBytes, totalBytes, Optional<Double>.none)
                continue
            }

            let written = try await fileDownloader.downloadFile(
                modelID: repoID,
                remotePath: file.path,
                to: fileURL,
                expectedSize: expectedSize,
                totalBytes: totalBytes,
                previouslyDownloaded: downloadedBytes
            )
            downloadedBytes += written
            await onProgress?(downloadedBytes, totalBytes, nil)
        }

        try validate(files: filtered, in: localDir)
        return localDir
    }

    private func validate(files: [CoworkMLXKleeHFFileEntry], in directory: URL) throws {
        let fm = FileManager.default
        var hasWeights = false
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            guard fm.fileExists(atPath: url.path) else {
                throw CoworkMLXKleeDownloadError.failed("Missing file: \(file.path)")
            }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            if let expected = file.size, expected > 0, size != expected {
                throw CoworkMLXKleeDownloadError.failed("Wrong size for \(file.path): expected \(expected), got \(size)")
            }
            if file.path.hasSuffix(".safetensors") {
                hasWeights = true
                guard size > 1_000_000 else {
                    throw CoworkMLXKleeDownloadError.failed("Invalid tiny safetensors file: \(file.path)")
                }
            }
        }
        guard hasWeights else {
            throw CoworkMLXKleeDownloadError.failed("No safetensors weights found")
        }
    }
}
