import Foundation

/// Plain cloud chat — bypasses CoworkCore's ACP agent runtime (which injects MCP/tools and breaks SOTA models like gpt-5.6-luna).
enum CoworkCloudDirectChat {
    struct Turn: Sendable {
        let role: String
        let content: String
    }

    enum ChatError: LocalizedError {
        case missingAPIKey
        case unsupportedPlatform(String)
        case emptyResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "Provider API key is missing."
            case .unsupportedPlatform(let p): return "Direct chat is not supported for platform \(p)."
            case .emptyResponse: return "The model returned an empty response."
            case .httpError(let code, let body): return "HTTP \(code): \(body)"
            }
        }
    }

    static func complete(
        provider: CoworkProvider,
        model: String,
        history: [Turn],
        userMessage: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        let apiKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let platform = provider.platform.lowercased()
        switch platform {
        case "openai", "xai", "openrouter", "custom", "infomaniak":
            return try await openAICompatibleChat(
                baseURL: provider.baseURL,
                apiKey: apiKey,
                model: model,
                history: history,
                userMessage: userMessage,
                systemPrompt: systemPrompt
            )
        case "anthropic":
            return try await anthropicChat(
                baseURL: provider.baseURL,
                apiKey: apiKey,
                model: model,
                history: history,
                userMessage: userMessage,
                systemPrompt: systemPrompt
            )
        case "gemini", "google":
            return try await geminiChat(
                baseURL: provider.baseURL,
                apiKey: apiKey,
                model: model,
                history: history,
                userMessage: userMessage,
                systemPrompt: systemPrompt
            )
        default:
            throw ChatError.unsupportedPlatform(platform)
        }
    }

    // MARK: - OpenAI-compatible (OpenAI, xAI, OpenRouter, custom)

    private static func openAICompatibleChat(
        baseURL: String,
        apiKey: String,
        model: String,
        history: [Turn],
        userMessage: String,
        systemPrompt: String?
    ) async throws -> String {
        var root = CoworkOllamaModelsAPI.normalizedChatBaseURL(baseURL)
        if !root.hasSuffix("/v1") { root += "/v1" }
        guard let url = URL(string: "\(root)/chat/completions") else {
            throw ChatError.httpError(0, "Invalid provider URL")
        }

        var messages: [[String: String]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        for turn in history where !turn.content.isEmpty {
            let role = turn.role == "assistant" ? "assistant" : "user"
            messages.append(["role": role, "content": turn.content])
        }
        messages.append(["role": "user", "content": userMessage])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_completion_tokens": 4096,
        ]

        let json = try await postJSON(url: url, apiKey: apiKey, headerStyle: .bearer, body: body)
        if let choice = (json["choices"] as? [[String: Any]])?.first {
            if let message = choice["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            if let text = choice["text"] as? String, !text.isEmpty {
                return text
            }
        }
        throw ChatError.emptyResponse
    }

    // MARK: - Anthropic

    private static func anthropicChat(
        baseURL: String,
        apiKey: String,
        model: String,
        history: [Turn],
        userMessage: String,
        systemPrompt: String?
    ) async throws -> String {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if !root.hasSuffix("/v1") { root += "/v1" }
        guard let url = URL(string: "\(root)/messages") else {
            throw ChatError.httpError(0, "Invalid Anthropic URL")
        }

        var messages: [[String: String]] = []
        for turn in history where !turn.content.isEmpty {
            let role = turn.role == "assistant" ? "assistant" : "user"
            messages.append(["role": role, "content": turn.content])
        }
        messages.append(["role": "user", "content": userMessage])

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": messages,
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        let json = try await postJSON(url: url, apiKey: apiKey, headerStyle: .anthropic, body: body)
        if let blocks = json["content"] as? [[String: Any]] {
            let text = blocks.compactMap { $0["text"] as? String }.joined()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        throw ChatError.emptyResponse
    }

    // MARK: - Gemini

    private static func geminiChat(
        baseURL: String,
        apiKey: String,
        model: String,
        history: [Turn],
        userMessage: String,
        systemPrompt: String?
    ) async throws -> String {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/v1beta", with: "")
            .replacingOccurrences(of: "/v1", with: "")
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let modelID = model.replacingOccurrences(of: "^models/", with: "", options: .regularExpression)
        guard let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(root)/v1beta/models/\(modelID):generateContent?key=\(encodedKey)") else {
            throw ChatError.httpError(0, "Invalid Gemini URL")
        }

        var contents: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            contents.append([
                "role": "user",
                "parts": [["text": systemPrompt]],
            ])
            contents.append([
                "role": "model",
                "parts": [["text": "OK."]],
            ])
        }
        for turn in history where !turn.content.isEmpty {
            let role = turn.role == "assistant" ? "model" : "user"
            contents.append(["role": role, "parts": [["text": turn.content]]])
        }
        contents.append(["role": "user", "parts": [["text": userMessage]]])

        let body: [String: Any] = ["contents": contents]
        let json = try await postJSON(url: url, apiKey: nil, headerStyle: .none, body: body)
        if let candidates = json["candidates"] as? [[String: Any]],
           let parts = candidates.first?["content"] as? [String: Any],
           let items = parts["parts"] as? [[String: Any]] {
            let text = items.compactMap { $0["text"] as? String }.joined()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        throw ChatError.emptyResponse
    }

    // MARK: - HTTP

    private enum HeaderStyle { case bearer, anthropic, none }

    private static func postJSON(
        url: URL,
        apiKey: String?,
        headerStyle: HeaderStyle,
        body: [String: Any]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatError.httpError(0, "No HTTP response")
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard (200 ... 299).contains(http.statusCode) else {
            throw ChatError.httpError(http.statusCode, String(raw.prefix(400)))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatError.httpError(http.statusCode, "Invalid JSON")
        }
        return json
    }
}
