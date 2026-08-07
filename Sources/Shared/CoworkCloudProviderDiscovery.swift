import Foundation

/// Direct cloud model discovery (Aisance `user-provider-models.ts`) — rich metadata without CoworkCore.
enum CoworkCloudProviderDiscovery {
    enum DiscoveryError: LocalizedError {
        case unsupportedProvider
        case emptyCatalog(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedProvider: return "Unsupported cloud provider."
            case .emptyCatalog(let detail): return detail
            }
        }
    }

    static func fetch(
        preset: CoworkProviderPreset,
        baseURL: String,
        apiKey: String,
        productId: String? = nil
    ) async throws -> [CoworkDiscoveredModel] {
        let platform = preset.platform.lowercased()
        let root = normalizedBase(baseURL, preset: preset)

        let models: [CoworkDiscoveredModel]
        switch platform {
        case "openai":
            models = try await fetchOpenAI(base: root, apiKey: apiKey, platform: platform)
        case "anthropic":
            models = try await fetchAnthropic(base: root, apiKey: apiKey, platform: platform)
        case "gemini", "google":
            models = try await fetchGemini(base: root, apiKey: apiKey, platform: platform)
        case "openrouter":
            models = try await fetchOpenRouter(base: root, apiKey: apiKey, platform: platform)
        case "xai":
            models = try await fetchXAI(base: root, apiKey: apiKey, platform: platform)
        case "infomaniak":
            models = try await fetchInfomaniak(apiKey: apiKey, productId: productId, platform: platform)
        case "custom":
            models = try await fetchOpenAICompatible(base: root, apiKey: apiKey, platform: platform)
        default:
            throw DiscoveryError.unsupportedProvider
        }

        guard !models.isEmpty else {
            throw DiscoveryError.emptyCatalog(L10n.noModelsFound)
        }
        return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - OpenAI

    private static func fetchOpenAI(base: String, apiKey: String, platform: String) async throws -> [CoworkDiscoveredModel] {
        let data = try await getJSON("\(base)/models", apiKey: apiKey, headerStyle: .bearer)
        guard let list = data["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let lower = id.lowercased()
            guard lower.contains("gpt")
                || lower.contains("o1")
                || lower.contains("o3")
                || lower.contains("o4")
                || lower.contains("chatgpt") else { return nil }
            let option = CoworkModelOption.named(id: id, name: id)
            var model = CoworkCloudModelCatalog.enrich(option, platform: platform)
            if let ctx = positiveInt(row["context_length"]) ?? positiveInt(row["context_window"]) {
                model.contextLength = ctx
            }
            return model
        }
    }

    // MARK: - Anthropic

    private static func fetchAnthropic(base: String, apiKey: String, platform: String) async throws -> [CoworkDiscoveredModel] {
        var all: [[String: Any]] = []
        var afterID: String?

        repeat {
            let pageURL = anthropicPageURL(base: base, afterID: afterID)
            let data = try await getJSON(pageURL.absoluteString, apiKey: apiKey, headerStyle: .anthropic)
            let batch = data["data"] as? [[String: Any]] ?? []
            all.append(contentsOf: batch)
            let hasMore = data["has_more"] as? Bool ?? false
            afterID = hasMore ? data["last_id"] as? String : nil
        } while afterID != nil

        if all.isEmpty {
            return CoworkCloudModelCatalog.fromOptions([], platform: platform)
        }

        return all.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let display = (row["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (display?.isEmpty == false) ? display! : id
            let ctx = positiveInt(row["max_input_tokens"]) ?? 200_000
            var model = CoworkCloudModelCatalog.enrich(.named(id: id, name: name), platform: platform)
            model.contextLength = ctx
            return model
        }
    }

    // MARK: - Gemini

    private static func fetchGemini(base: String, apiKey: String, platform: String) async throws -> [CoworkDiscoveredModel] {
        let root = base.replacingOccurrences(of: "/v1beta", with: "").replacingOccurrences(of: "/v1", with: "")
        let url = "\(root)/v1beta/models?key=\(apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey)"
        let data = try await getJSON(url, apiKey: nil, headerStyle: .none)
        guard let list = data["models"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let full = row["name"] as? String else { return nil }
            let id = full.replacingOccurrences(of: "models/", with: "")
            guard id.contains("gemini") else { return nil }
            let display = (row["displayName"] as? String) ?? id
            var model = CoworkCloudModelCatalog.enrich(.named(id: id, name: display), platform: platform)
            if let tokens = positiveInt(row["inputTokenLimit"]) {
                model.contextLength = tokens
            }
            return model
        }
    }

    // MARK: - OpenRouter

    private static func fetchOpenRouter(base: String, apiKey: String, platform: String) async throws -> [CoworkDiscoveredModel] {
        let data = try await getJSON("\(base)/models", apiKey: apiKey, headerStyle: .bearer)
        guard let list = data["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String,
                  let name = row["name"] as? String else { return nil }
            var model = CoworkDiscoveredModel(
                id: id,
                name: name,
                provider: platform,
                description: row["description"] as? String,
                contextLength: positiveInt(row["context_length"]),
                inputPricePerMillion: nil,
                outputPricePerMillion: nil
            )
            if let pricing = row["pricing"] as? [String: Any] {
                if let prompt = double(pricing["prompt"]) {
                    model.inputPricePerMillion = prompt * 1_000_000
                }
                if let completion = double(pricing["completion"]) {
                    model.outputPricePerMillion = completion * 1_000_000
                }
            }
            return model
        }
    }

    // MARK: - xAI

    private static func fetchXAI(base: String, apiKey: String, platform: String) async throws -> [CoworkDiscoveredModel] {
        if let rich = try? await getJSON("\(base)/language-models", apiKey: apiKey, headerStyle: .bearer),
           let list = rich["models"] as? [[String: Any]], !list.isEmpty {
            return list.compactMap { row in
                guard let id = (row["id"] as? String) ?? (row["name"] as? String) else { return nil }
                let name = (row["name"] as? String) ?? id
                let ctx = positiveInt(row["max_prompt_length"]) ?? positiveInt(row["context_length"])
                var model = CoworkCloudModelCatalog.enrich(.named(id: id, name: name), platform: platform)
                model.contextLength = ctx
                model.description = row["description"] as? String ?? model.description
                return model
            }
        }
        let data = try await getJSON("\(base)/models", apiKey: apiKey, headerStyle: .bearer)
        guard let list = data["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String, id.contains("grok") else { return nil }
            return CoworkCloudModelCatalog.enrich(.named(id: id, name: id), platform: platform)
        }
    }

    // MARK: - Infomaniak

    private static func fetchInfomaniak(apiKey: String, productId: String?, platform: String) async throws -> [CoworkDiscoveredModel] {
        let base = "https://api.infomaniak.com"
        var productIDs: [String] = []
        if let productId, !productId.isEmpty {
            productIDs = [productId]
        } else {
            let productsData = try await getJSON("\(base)/1/ai", apiKey: apiKey, headerStyle: .bearer)
            let products = productsData["data"] as? [[String: Any]] ?? []
            productIDs = products.compactMap { row in
                if let pid = row["product_id"] { return String(describing: pid) }
                if let id = row["id"] { return String(describing: id) }
                return nil
            }
            if productIDs.isEmpty {
                throw DiscoveryError.emptyCatalog(L10n.infomaniakNoProducts)
            }
        }

        var all: [CoworkDiscoveredModel] = []
        var seen = Set<String>()
        for pid in productIDs {
            let data = try await getJSON("\(base)/2/ai/\(pid)/openai/v1/models", apiKey: apiKey, headerStyle: .bearer)
            let list = data["data"] as? [[String: Any]] ?? []
            for row in list {
                guard let id = row["id"] as? String, !seen.contains(id) else { continue }
                seen.insert(id)
                var model = CoworkCloudModelCatalog.enrich(.named(id: id, name: id), platform: platform)
                model.description = row["description"] as? String ?? "Infomaniak kAI \(id)"
                if let ctx = positiveInt(row["context_length"]) {
                    model.contextLength = ctx
                }
                all.append(model)
            }
        }
        return all
    }

    // MARK: - OpenAI-compatible custom

    private static func fetchOpenAICompatible(base: String, apiKey: String, platform: String) async throws -> [CoworkDiscoveredModel] {
        let data = try await getJSON("\(base)/models", apiKey: apiKey, headerStyle: .bearer)
        guard let list = data["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let name = (row["name"] as? String) ?? id
            return CoworkCloudModelCatalog.enrich(.named(id: id, name: name), platform: platform)
        }
    }

    // MARK: - HTTP

    private enum HeaderStyle { case bearer, anthropic, none }

    private static func getJSON(
        _ urlString: String,
        apiKey: String?,
        headerStyle: HeaderStyle
    ) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw DiscoveryError.emptyCatalog("Invalid URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        switch headerStyle {
        case .bearer:
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        case .none:
            break
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DiscoveryError.emptyCatalog("No HTTP response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DiscoveryError.emptyCatalog("HTTP \(http.statusCode): \(body.prefix(200))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiscoveryError.emptyCatalog("Invalid JSON")
        }
        return json
    }

    private static func normalizedBase(_ baseURL: String, preset: CoworkProviderPreset) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return preset.defaultBaseURL.replacingOccurrences(of: "/$", with: "", options: .regularExpression) }
        var root = trimmed.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if preset == .openAI || preset == .xai || preset == .openRouter, !root.hasSuffix("/v1") {
            root += "/v1"
        }
        return root
    }

    private static func anthropicPageURL(base: String, afterID: String?) -> URL {
        var root = base.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if !root.hasSuffix("/v1") { root += "/v1" }
        var components = URLComponents(string: "\(root)/models")!
        var items = [URLQueryItem(name: "limit", value: "100")]
        if let afterID { items.append(URLQueryItem(name: "after_id", value: afterID)) }
        components.queryItems = items
        return components.url!
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        if let n = value as? Int, n > 0 { return n }
        if let n = value as? Double, n > 0 { return Int(n) }
        if let s = value as? String, let n = Int(s), n > 0 { return n }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
