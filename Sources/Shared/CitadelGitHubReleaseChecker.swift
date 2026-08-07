import Foundation

struct CitadelGitHubRelease: Decodable, Sendable, Equatable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }

    struct Asset: Decodable, Sendable, Equatable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    var version: String { CitadelVersionCompare.normalize(tagName) }

    var preferredDownloadURL: URL? {
        assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })?.browserDownloadURL
            ?? assets.first?.browserDownloadURL
            ?? htmlURL
    }
}

enum CitadelVersionCompare {
    static func normalize(_ version: String) -> String {
        var value = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("v") {
            value.removeFirst()
        }
        return value
    }

    static func isRemoteNewer(remote: String, local: String) -> Bool {
        compare(remote, local) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parse(normalize(lhs))
        let right = parse(normalize(rhs))
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b {
                return a > b ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }

    private static func parse(_ normalized: String) -> [Int] {
        normalized.split(separator: ".", omittingEmptySubsequences: false).map { part in
            let numeric = part.prefix { $0.isNumber }
            return Int(numeric) ?? 0
        }
    }
}

enum CitadelGitHubReleaseAPI {
    static func fetchLatest(session: URLSession = .shared) async throws -> CitadelGitHubRelease {
        var request = URLRequest(url: AppConstants.githubLatestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Citadel/\(AppConstants.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CitadelGitHubReleaseError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CitadelGitHubReleaseError.httpStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(CitadelGitHubRelease.self, from: data)
        } catch {
            throw CitadelGitHubReleaseError.decodingFailed
        }
    }
}

enum CitadelGitHubReleaseError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid update check response."
        case .httpStatus(let code):
            return "Update check failed (HTTP \(code))."
        case .decodingFailed:
            return "Could not read the latest release information."
        }
    }
}
