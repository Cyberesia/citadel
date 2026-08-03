import Foundation

private final class CoworkMLXKleeDelegateContext: @unchecked Sendable {
    nonisolated(unsafe) var continuation: CheckedContinuation<(URL, URLResponse), any Error>?
    nonisolated(unsafe) var stagingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("citadel-klee-download-staging", isDirectory: true)
    nonisolated(unsafe) var speedBytesAccumulator: Int64 = 0
    nonisolated(unsafe) var lastSpeedUpdate = Date.now
    nonisolated(unsafe) var lastReportedTotalWritten: Int64 = 0
    nonisolated(unsafe) var filePreviouslyDownloaded: Int64 = 0
    nonisolated(unsafe) var fileResumeOffset: Int64 = 0
    nonisolated(unsafe) var totalBytes: Int64 = 0
    nonisolated(unsafe) var resumeDataURL: URL?
}

final class CoworkMLXKleeFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    nonisolated private let ctx = CoworkMLXKleeDelegateContext()

    private var downloadSession: URLSession = .shared
    private var activeDownloadTask: URLSessionDownloadTask?

    var onProgress: CoworkMLXKleeDownloadProgressCallback?

    nonisolated override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        try? FileManager.default.createDirectory(at: ctx.stagingDirectory, withIntermediateDirectories: true)
    }

    func pauseActiveTask() {
        guard let task = activeDownloadTask else { return }
        task.cancel { [ctx] resumeData in
            guard let resumeData, let url = ctx.resumeDataURL else { return }
            try? resumeData.write(to: url, options: [.atomic])
        }
        activeDownloadTask = nil
    }

    func cancelActiveTask() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        if let url = ctx.resumeDataURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func downloadFile(
        modelID: String,
        remotePath: String,
        to localURL: URL,
        expectedSize: Int64,
        totalBytes: Int64,
        previouslyDownloaded: Int64
    ) async throws -> Int64 {
        let encodedPath = remotePath.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let urlString = "\(CoworkMLXKleeHuggingFaceAPI.resolvedEndpoint())/\(modelID)/resolve/main/\(encodedPath)?download=true"
        guard let url = URL(string: urlString) else {
            throw CoworkMLXKleeDownloadError.failed("Invalid download URL for \(remotePath)")
        }

        let fm = FileManager.default
        let incompleteURL = localURL.appendingPathExtension("incomplete")
        let resumeDataURL = localURL.appendingPathExtension("resumeData")

        if fm.fileExists(atPath: localURL.path) {
            if let attrs = try? fm.attributesOfItem(atPath: localURL.path),
               let size = attrs[.size] as? Int64,
               expectedSize > 0,
               size == expectedSize {
                return expectedSize
            }
            try? fm.removeItem(at: localURL)
        }

        var resumeOffset: Int64 = 0
        if fm.fileExists(atPath: incompleteURL.path) {
            let attrs = try fm.attributesOfItem(atPath: incompleteURL.path)
            resumeOffset = attrs[.size] as? Int64 ?? 0
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 600
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }

        ctx.speedBytesAccumulator = 0
        ctx.lastSpeedUpdate = .now
        ctx.lastReportedTotalWritten = 0
        ctx.filePreviouslyDownloaded = previouslyDownloaded
        ctx.fileResumeOffset = resumeOffset
        ctx.totalBytes = totalBytes
        ctx.resumeDataURL = resumeDataURL

        let (stagedURL, response) = try await withCheckedThrowingContinuation { continuation in
            self.ctx.continuation = continuation
            let task: URLSessionDownloadTask
            if let resumeData = try? Data(contentsOf: resumeDataURL), !resumeData.isEmpty {
                task = self.downloadSession.downloadTask(withResumeData: resumeData)
            } else {
                task = self.downloadSession.downloadTask(with: request)
            }
            self.activeDownloadTask = task
            task.resume()
        }
        activeDownloadTask = nil

        guard let http = response as? HTTPURLResponse else {
            try? fm.removeItem(at: stagedURL)
            throw CoworkMLXKleeDownloadError.failed("Invalid response for \(remotePath)")
        }

        switch http.statusCode {
        case 200:
            resumeOffset = 0
            try? fm.removeItem(at: incompleteURL)
            try? fm.removeItem(at: resumeDataURL)
            try fm.moveItem(at: stagedURL, to: incompleteURL)
        case 206:
            if !fm.fileExists(atPath: incompleteURL.path) {
                fm.createFile(atPath: incompleteURL.path, contents: nil)
            }
            let writer = try FileHandle(forWritingTo: incompleteURL)
            let reader = try FileHandle(forReadingFrom: stagedURL)
            do {
                try writer.seekToEnd()
                while true {
                    let chunk = reader.readData(ofLength: 4 * 1024 * 1024)
                    if chunk.isEmpty { break }
                    try writer.write(contentsOf: chunk)
                }
                try writer.close()
                try reader.close()
            } catch {
                try? writer.close()
                try? reader.close()
                throw error
            }
            try? fm.removeItem(at: stagedURL)
            try? fm.removeItem(at: resumeDataURL)
        case 416:
            try? fm.removeItem(at: incompleteURL)
            try? fm.removeItem(at: stagedURL)
            return try await downloadFile(
                modelID: modelID,
                remotePath: remotePath,
                to: localURL,
                expectedSize: expectedSize,
                totalBytes: totalBytes,
                previouslyDownloaded: previouslyDownloaded
            )
        default:
            try? fm.removeItem(at: stagedURL)
            throw CoworkMLXKleeDownloadError.failed("HTTP \(http.statusCode) downloading \(remotePath)")
        }

        let attrs = try fm.attributesOfItem(atPath: incompleteURL.path)
        let bytesWritten = attrs[.size] as? Int64 ?? 0
        if expectedSize > 0 && bytesWritten != expectedSize {
            throw CoworkMLXKleeDownloadError.failed(
                "Size mismatch for \(remotePath): expected \(expectedSize), got \(bytesWritten)"
            )
        }

        try? fm.removeItem(at: localURL)
        try fm.moveItem(at: incompleteURL, to: localURL)
        try? fm.removeItem(at: resumeDataURL)
        return bytesWritten
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let delta = totalBytesWritten - ctx.lastReportedTotalWritten
        ctx.lastReportedTotalWritten = totalBytesWritten
        ctx.speedBytesAccumulator += delta

        let now = Date.now
        let elapsed = now.timeIntervalSince(ctx.lastSpeedUpdate)
        var speed: Double?
        if elapsed >= 0.5 {
            speed = Double(ctx.speedBytesAccumulator) / elapsed
            ctx.speedBytesAccumulator = 0
            ctx.lastSpeedUpdate = now
        }

        let downloaded = ctx.filePreviouslyDownloaded + ctx.fileResumeOffset + totalBytesWritten
        let total = ctx.totalBytes
        Task { @MainActor [weak self, speed] in
            self?.onProgress?(downloaded, total, speed)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let stagedFile = ctx.stagingDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: stagedFile)
            if let response = downloadTask.response {
                ctx.continuation?.resume(returning: (stagedFile, response))
            } else {
                ctx.continuation?.resume(throwing: CoworkMLXKleeDownloadError.failed("No response from download task"))
            }
        } catch {
            ctx.continuation?.resume(throwing: error)
        }
        ctx.continuation = nil
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            ctx.continuation?.resume(throwing: error)
            ctx.continuation = nil
        }
    }
}
