import Foundation

/// Persists direct Ollama/cloud chat turns that never go through CoworkCore's agent message API.
/// Without this, `loadMessages` / view `onAppear` wipe the in-memory transcript and leave only a thinking card.
enum CoworkDirectChatStore {
    struct Entry: Codable, Equatable {
        var id: String
        var conversationID: String
        var position: String
        var text: String
        var createdAt: Double?
        var thinking: String?
        var thinkingFinishedAt: Double?
        var thinkingExpanded: Bool?
    }

    struct Transcript: Codable, Equatable {
        var messages: [Entry]
    }

    private static let folderName = "DirectChatTranscripts"

    static func load(conversationID: String) -> Transcript {
        guard let url = fileURL(for: conversationID),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Transcript.self, from: data)
        else {
            return Transcript(messages: [])
        }
        return decoded
    }

    static func save(conversationID: String, messages: [CoworkMessage], thinkingByMsgID: [String: CoworkArchivedThinking]) {
        let entries: [Entry] = messages.compactMap { message in
            guard message.hidden != true, !message.isTips, !message.isToolMessage else { return nil }
            let id = message.msgID ?? message.id
            guard let id, !id.isEmpty else { return nil }
            let body = message.textBody
            let archived = thinkingByMsgID[id]
            // Keep empty assistant shells only when we still have reasoning to show.
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               (archived?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                return nil
            }
            return Entry(
                id: id,
                conversationID: conversationID,
                position: message.position ?? (message.isUser ? "right" : "left"),
                text: body,
                createdAt: message.createdAt,
                thinking: archived?.text,
                thinkingFinishedAt: archived.map { $0.finishedAt.timeIntervalSince1970 },
                thinkingExpanded: archived?.cardExpanded
            )
        }
        let transcript = Transcript(messages: entries)
        guard let url = fileURL(for: conversationID) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(transcript) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    static func coworkMessages(from transcript: Transcript) -> [CoworkMessage] {
        transcript.messages.map { entry in
            CoworkMessage(
                localID: entry.id,
                conversationID: entry.conversationID,
                position: entry.position,
                text: entry.text
            )
        }
    }

    static func archivedThinking(from transcript: Transcript) -> [String: CoworkArchivedThinking] {
        var result: [String: CoworkArchivedThinking] = [:]
        for entry in transcript.messages {
            guard let thinking = entry.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !thinking.isEmpty else { continue }
            let finished = entry.thinkingFinishedAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
            result[entry.id] = CoworkArchivedThinking(
                text: thinking,
                finishedAt: finished,
                cardExpanded: entry.thinkingExpanded
            )
        }
        return result
    }

    /// Server page first, then any local-only direct-chat turns (by msg id).
    static func merge(server: [CoworkMessage], local: [CoworkMessage]) -> [CoworkMessage] {
        var seen = Set(server.compactMap { $0.msgID ?? $0.id })
        var merged = server
        for message in local {
            let id = message.msgID ?? message.id
            guard let id else {
                merged.append(message)
                continue
            }
            if seen.contains(id) { continue }
            seen.insert(id)
            merged.append(message)
        }
        return merged
    }

    private static func fileURL(for conversationID: String) -> URL? {
        let trimmed = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let safe = trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Citadel", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        return root?.appendingPathComponent("\(safe).json", isDirectory: false)
    }
}
