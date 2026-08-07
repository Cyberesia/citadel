import Foundation

/// Murmura-style Ollama `/api/chat` stream with `think: true` so reasoning models
/// emit `message.thinking` live (wrapped as `<think>…</think>` for the UI parser).
enum CoworkOllamaChatStream {
    struct ChatError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let think: Bool?
        let options: [String: Int]?

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct StreamPacket: Decodable {
        struct Message: Decodable {
            let content: String?
            let thinking: String?
        }
        let message: Message?
        let done: Bool?
    }

    /// Streams assistant deltas. Thinking chunks are wrapped in `<think>` tags.
    static func streamResponse(
        baseURL: String,
        model: String,
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        let root = try nativeRootURL(from: baseURL)
        let chatURL = root.appendingPathComponent("api").appendingPathComponent("chat")

        var composed = messages.map { ChatRequest.Message(role: $0.role, content: $0.content) }
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            composed.insert(ChatRequest.Message(role: "system", content: systemPrompt), at: 0)
        }

        let body = ChatRequest(
            model: model,
            messages: composed,
            stream: true,
            think: true,
            options: ["num_ctx": 32_768]
        )
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 600

        let session = URLSession(configuration: .ephemeral)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatError(message: "Invalid Ollama response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ChatError(message: "Ollama HTTP \(http.statusCode). Is `ollama serve` running?")
        }

        var reasoningTagOpen = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty, line.hasPrefix("{"),
                  let data = line.data(using: .utf8),
                  let packet = try? JSONDecoder().decode(StreamPacket.self, from: data)
            else { continue }

            if let thinking = packet.message?.thinking, !thinking.isEmpty {
                if !reasoningTagOpen {
                    await onDelta("<think>")
                    reasoningTagOpen = true
                }
                await onDelta(thinking)
            }

            if let piece = packet.message?.content, !piece.isEmpty {
                if reasoningTagOpen {
                    await onDelta("</think>")
                    reasoningTagOpen = false
                }
                await onDelta(piece)
            }

            if packet.done == true { break }
        }

        if reasoningTagOpen {
            await onDelta("</think>")
        }
    }

    static func nativeRootURL(from raw: String) throws -> URL {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw ChatError(message: "Invalid Ollama URL.") }
        if base.hasSuffix("/v1") { base = String(base.dropLast(3)) }
        while base.hasSuffix("/") { base.removeLast() }
        if let url = URL(string: base), url.scheme != nil { return url }
        if let url = URL(string: "http://\(base)") { return url }
        throw ChatError(message: "Invalid Ollama URL.")
    }
}
