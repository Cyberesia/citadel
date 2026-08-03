import Foundation
import Network
import MLXLMCommon

/// Minimal OpenAI-compatible HTTP server so CoworkCore can talk to native MLX on :8765.
actor CoworkMLXOpenAIServer {
    static let shared = CoworkMLXOpenAIServer()

    private var listener: NWListener?
    private var loadedRepoID: String?
    private let queue = DispatchQueue(label: "com.citadel.mlx.openai", qos: .userInitiated)

    var isRunning: Bool {
        if case .ready = listener?.state { return true }
        return false
    }

    func stop() {
        listener?.cancel()
        listener = nil
        loadedRepoID = nil
    }

    func start(
        port: Int,
        repoID: String,
        status: (@MainActor (String?) -> Void)? = nil
    ) async throws {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoworkMLXBridgeError.invalidModelID }

        if isRunning, loadedRepoID == trimmed { return }

        stop()
        await CoworkMLXNativeRuntime.shared.unload()

        await MainActor.run { status?("Setting up on-device AI…") }
        try await CoworkMLXNativeRuntime.shared.preloadChatModel(modelID: trimmed) { message in
            Task { @MainActor in status?(message) }
        }
        loadedRepoID = trimmed
        await MainActor.run { status?(nil) }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw CoworkMLXBridgeError.serverStartFailed("Invalid port \(port)")
        }

        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handle(connection: connection) }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: CoworkMLXBridgeError.serverStartFailed(error.localizedDescription))
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: CoworkMLXBridgeError.serverStartFailed("Listener cancelled"))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    // MARK: - HTTP

    private func handle(connection: NWConnection) async {
        connection.start(queue: queue)
        defer { connection.cancel() }

        do {
            let request = try await readRequest(on: connection)
            let response = try await route(request)
            try await send(response, on: connection)
        } catch {
            let body = "{\"error\":{\"message\":\"\(error.localizedDescription)\"}}"
            let response = HTTPResponse(
                status: 500,
                headers: ["Content-Type": "application/json"],
                body: Data(body.utf8)
            )
            try? await send(response, on: connection)
        }
    }

    private func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/v1/models"), ("GET", "/models"):
            return modelsListResponse()
        case ("POST", "/v1/chat/completions"), ("POST", "/chat/completions"):
            return try await chatCompletions(request)
        case ("GET", "/health"), ("GET", "/"):
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok".utf8))
        default:
            return HTTPResponse(status: 404, headers: ["Content-Type": "application/json"], body: Data("{\"error\":\"not found\"}".utf8))
        }
    }

    private func modelsListResponse() -> HTTPResponse {
        let modelID = loadedRepoID ?? CoworkMLXNativeRuntime.defaultHuggingFaceRepoID
        let json = """
        {"object":"list","data":[{"id":"\(modelID)","object":"model","owned_by":"citadel"}]}
        """
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(json.utf8))
    }

    private func chatCompletions(_ request: HTTPRequest) async throws -> HTTPResponse {
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: request.body)
        let modelID = (decoded.model?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? loadedRepoID
            ?? CoworkMLXNativeRuntime.defaultHuggingFaceRepoID

        let parsed = parseMessages(decoded.messages)
        let stream = decoded.stream ?? false

        if stream {
            return HTTPResponse.streaming(
                status: 200,
                headers: [
                    "Content-Type": "text/event-stream",
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                ]
            ) { writer in
                let id = UUID().uuidString
                let tokenStream = try await CoworkMLXNativeRuntime.shared.streamAssistantChat(
                    modelID: modelID,
                    instructions: parsed.instructions,
                    history: parsed.history,
                    latestUser: parsed.latestUser
                )
                for try await delta in tokenStream {
                    let chunk = Self.sseChunk(id: id, model: modelID, content: delta)
                    try await writer(chunk)
                }
                try await writer(Data("data: [DONE]\n\n".utf8))
            }
        }

        let text = try await CoworkMLXNativeRuntime.shared.complete(
            system: parsed.instructions ?? "",
            user: parsed.latestUser,
            numCtx: 8192,
            modelID: modelID
        )
        let json = Self.chatCompletionJSON(model: modelID, content: text)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(json.utf8))
    }

    private struct ParsedMessages {
        let instructions: String?
        let history: [Chat.Message]
        let latestUser: String
    }

    private func parseMessages(_ messages: [ChatCompletionRequest.Message]) -> ParsedMessages {
        var systemParts: [String] = []
        var turns: [(role: String, content: String)] = []

        for message in messages {
            let role = message.role.lowercased()
            let content = message.content ?? ""
            switch role {
            case "system":
                if !content.isEmpty { systemParts.append(content) }
            case "user", "assistant":
                turns.append((role, content))
            default:
                break
            }
        }

        var history: [Chat.Message] = []
        var latestUser = ""

        if let last = turns.last, last.role == "user" {
            latestUser = last.content
            turns.removeLast()
        } else if let last = turns.last {
            latestUser = last.content
            turns.removeLast()
        }

        for turn in turns {
            switch turn.role {
            case "user":
                history.append(.user(turn.content))
            case "assistant":
                history.append(.assistant(turn.content))
            default:
                break
            }
        }

        return ParsedMessages(
            instructions: systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n"),
            history: history,
            latestUser: latestUser
        )
    }

    private static func sseChunk(id: String, model: String, content: String) -> Data {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let payload = """
        {"id":"\(id)","object":"chat.completion.chunk","model":"\(model)","choices":[{"index":0,"delta":{"content":"\(escaped)"},"finish_reason":null}]}
        """
        return Data("data: \(payload)\n\n".utf8)
    }

    private static func chatCompletionJSON(model: String, content: String) -> String {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return """
        {"id":"\(UUID().uuidString)","object":"chat.completion","model":"\(model)","choices":[{"index":0,"message":{"role":"assistant","content":"\(escaped)"},"finish_reason":"stop"}]}
        """
    }

    // MARK: - Wire protocol helpers

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private struct HTTPResponse {
        typealias StreamBody = @Sendable (@Sendable (Data) async throws -> Void) async throws -> Void

        let status: Int
        let headers: [String: String]
        let body: Data?
        let streamBody: StreamBody?

        init(status: Int, headers: [String: String], body: Data) {
            self.status = status
            self.headers = headers
            self.body = body
            self.streamBody = nil
        }

        static func streaming(
            status: Int,
            headers: [String: String],
            body: @escaping StreamBody
        ) -> HTTPResponse {
            HTTPResponse(status: status, headers: headers, body: nil, streamBody: body)
        }

        private init(status: Int, headers: [String: String], body: Data?, streamBody: StreamBody?) {
            self.status = status
            self.headers = headers
            self.body = body
            self.streamBody = streamBody
        }
    }

    private func readRequest(on connection: NWConnection) async throws -> HTTPRequest {
        var buffer = Data()
        while true {
            let chunk = try await receive(on: connection, max: 65_536)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer[..<headerEnd.lowerBound]
                var body = Data(buffer[headerEnd.upperBound...])
                guard let headerText = String(data: headerData, encoding: .utf8) else {
                    throw CoworkMLXBridgeError.serverStartFailed("Invalid HTTP headers")
                }
                let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
                guard let requestLine = lines.first else {
                    throw CoworkMLXBridgeError.serverStartFailed("Missing request line")
                }
                let parts = requestLine.split(separator: " ")
                guard parts.count >= 2 else {
                    throw CoworkMLXBridgeError.serverStartFailed("Malformed request line")
                }
                let method = String(parts[0])
                let path = String(parts[1]).components(separatedBy: "?").first ?? "/"
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                    let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }
                if let lengthRaw = headers["content-length"], let length = Int(lengthRaw) {
                    while body.count < length {
                        let more = try await receive(on: connection, max: 65_536)
                        if more.isEmpty { break }
                        body.append(more)
                    }
                    if body.count > length {
                        body = body.prefix(length)
                    }
                }
                return HTTPRequest(method: method, path: path, headers: headers, body: body)
            }
            if buffer.count > 1_048_576 {
                throw CoworkMLXBridgeError.serverStartFailed("HTTP header too large")
            }
        }
        throw CoworkMLXBridgeError.serverStartFailed("Connection closed before request")
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) async throws {
        var header = "HTTP/1.1 \(response.status) \(statusText(response.status))\r\n"
        var headers = response.headers
        if let body = response.body {
            headers["Content-Length"] = "\(body.count)"
        }
        for (key, value) in headers {
            header += "\(key): \(value)\r\n"
        }
        header += "\r\n"
        try await send(Data(header.utf8), on: connection)

        if let streamBody = response.streamBody {
            try await streamBody { chunk in
                try await self.send(chunk, on: connection)
            }
        } else if let body = response.body {
            try await send(body, on: connection)
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receive(on connection: NWConnection, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Error"
        }
    }
}

private struct ChatCompletionRequest: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String?
    }

    let model: String?
    let messages: [Message]
    let stream: Bool?
}
