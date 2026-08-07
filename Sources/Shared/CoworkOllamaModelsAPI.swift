import Foundation

/// Direct Ollama model discovery (`GET /api/tags`) — same approach as Murmura.
enum CoworkOllamaModelsAPI {
    private struct TagsResponse: Decodable {
        struct Entry: Decodable {
            let name: String
            let capabilities: [String]?
            struct Details: Decodable {
                let family: String?
                let families: [String]?
            }
            let details: Details?
        }
        let models: [Entry]
    }

    struct OllamaModel: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let isEmbedding: Bool
        let supportsTools: Bool
    }

    enum FetchError: LocalizedError {
        case invalidURL
        case badStatus(Int)
        case decode

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Ollama URL."
            case .badStatus(let code): return "Ollama returned HTTP \(code). Is `ollama serve` running?"
            case .decode: return "Could not parse Ollama /api/tags response."
            }
        }
    }

    static func fetchInstalledModels(baseURL: String) async throws -> [OllamaModel] {
        let root = try normalizedRootURL(from: baseURL)
        let tagsURL = root.appendingPathComponent("api").appendingPathComponent("tags")

        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            throw FetchError.decode
        }

        return decoded.models.map { entry in
            let lowName = entry.name.lowercased()
            let isEmbedding = lowName.contains("embed")
                || lowName.contains("nomic")
                || entry.details?.family?.lowercased() == "bert"
                || entry.details?.families?.contains(where: { $0.lowercased() == "bert" }) == true
            let supportsTools: Bool
            if let capabilities = entry.capabilities {
                supportsTools = capabilities.contains(where: { $0.lowercased() == "tools" })
            } else {
                supportsTools = CoworkModelToolSupport.heuristicForModelName(entry.name)
            }
            return OllamaModel(name: entry.name, isEmbedding: isEmbedding, supportsTools: supportsTools)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func normalizedChatBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        var url = trimmed
        while url.hasSuffix("/") { url.removeLast() }
        if url.contains("11434") || url.contains("1234") {
            if !url.hasSuffix("/v1") { url += "/v1" }
        }
        return url
    }

    private static func normalizedRootURL(from raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FetchError.invalidURL }
        var base = trimmed
        if base.hasSuffix("/v1") { base = String(base.dropLast(3)) }
        while base.hasSuffix("/") { base.removeLast() }
        if let url = URL(string: base), url.scheme != nil { return url }
        if let url = URL(string: "http://\(base)") { return url }
        throw FetchError.invalidURL
    }
}
