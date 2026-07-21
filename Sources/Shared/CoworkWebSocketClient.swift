import Foundation

@MainActor
final class CoworkWebSocketClient: NSObject, ObservableObject {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var handlers: [String: [(Data) -> Void]] = [:]
    private var receiveLoopRunning = false
    private var lastURL: URL?
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var intentionalDisconnect = false

    func connect(url: URL) {
        disconnect()
        lastURL = url
        intentionalDisconnect = false
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoopRunning = true
        receiveNext()
    }

    func disconnect(clearHandlers: Bool = false) {
        intentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveLoopRunning = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if clearHandlers {
            handlers = [:]
        }
    }

    func on(event: String, handler: @escaping (Data) -> Void) {
        var list = handlers[event] ?? []
        list.append(handler)
        handlers[event] = list
    }

    private func receiveNext() {
        guard receiveLoopRunning, let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.reconnectAttempts = 0
                    self.handle(message)
                    self.receiveNext()
                case .failure:
                    self.receiveLoopRunning = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    /// Auto-reconnect with capped exponential backoff so streaming survives core hiccups.
    private func scheduleReconnect() {
        guard !intentionalDisconnect, let url = lastURL else { return }
        reconnectAttempts += 1
        let delay = min(10.0, pow(2.0, Double(min(reconnectAttempts, 4))))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard !self.intentionalDisconnect else { return }
            self.connect(url: url)
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8)
        @unknown default: data = nil
        }
        guard let data else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let eventName = (json["name"] as? String) ?? (json["event"] as? String)
        guard let eventName else { return }

        let payloadData: Data
        if let payload = json["data"] ?? json["payload"] {
            payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? data
        } else {
            payloadData = data
        }

        for handler in handlers[eventName] ?? [] {
            handler(payloadData)
        }
    }
}
