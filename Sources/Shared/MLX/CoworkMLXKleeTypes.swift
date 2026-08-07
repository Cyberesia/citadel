import Foundation

struct CoworkMLXKleeHFFileEntry: Decodable, Sendable {
    let type: String
    let path: String
    let size: Int64?
}

enum CoworkMLXKleeDownloadError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let detail):
            return "MLX model download failed: \(detail)"
        }
    }
}

typealias CoworkMLXKleeDownloadProgressCallback = @MainActor (
    _ downloadedBytes: Int64,
    _ totalBytes: Int64,
    _ speedBytesPerSecond: Double?
) -> Void
