import Foundation

/// Batches WebSocket text chunks before UI/parser updates (Murmura Assistant coalescing).
@MainActor
final class CoworkStreamDeltaCoalescer {
    private struct Session {
        var buffer = ""
        var debounceTask: Task<Void, Never>?
        var tailTask: Task<Void, Never>?
    }

    private var sessions: [String: Session] = [:]

    /// Answer + thinking — Murmura uses one bucket (~560 / 22ms). Tiny thinking flushes were nuking FPS.
    private static let answerSizeThreshold = 560
    private static let answerDebounceNanoseconds: UInt64 = 22_000_000
    private static let thinkingSizeThreshold = 560
    private static let thinkingDebounceNanoseconds: UInt64 = 22_000_000

    func reset(msgID: String) {
        sessions[msgID]?.debounceTask?.cancel()
        sessions[msgID]?.tailTask?.cancel()
        sessions.removeValue(forKey: msgID)
    }

    func resetAll() {
        for msgID in sessions.keys {
            reset(msgID: msgID)
        }
    }

    func enqueue(
        msgID: String,
        piece: String,
        preferFastFlush: Bool,
        onFlush: @escaping @MainActor (String) -> Void
    ) {
        guard !piece.isEmpty else { return }
        var session = sessions[msgID] ?? Session()
        session.buffer.append(piece)
        sessions[msgID] = session

        let threshold = preferFastFlush ? Self.thinkingSizeThreshold : Self.answerSizeThreshold
        if session.buffer.utf16.count >= threshold {
            session.debounceTask?.cancel()
            session.debounceTask = nil
            sessions[msgID] = session
            scheduleDrain(msgID: msgID, isFinal: false, onFlush: onFlush)
            return
        }

        let debounce = preferFastFlush ? Self.thinkingDebounceNanoseconds : Self.answerDebounceNanoseconds
        session.debounceTask?.cancel()
        session.debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            scheduleDrain(msgID: msgID, isFinal: false, onFlush: onFlush)
        }
        sessions[msgID] = session
    }

    func flush(msgID: String, onFlush: @escaping @MainActor (String) -> Void) async {
        sessions[msgID]?.debounceTask?.cancel()
        sessions[msgID]?.debounceTask = nil
        if let tail = sessions[msgID]?.tailTask {
            await tail.value
        }
        await drain(msgID: msgID, isFinal: true, onFlush: onFlush)
    }

    private func scheduleDrain(
        msgID: String,
        isFinal: Bool,
        onFlush: @escaping @MainActor (String) -> Void
    ) {
        let previous = sessions[msgID]?.tailTask
        let task = Task { @MainActor in
            if let previous { await previous.value }
            await drain(msgID: msgID, isFinal: isFinal, onFlush: onFlush)
        }
        sessions[msgID]?.tailTask = task
    }

    private func drain(
        msgID: String,
        isFinal: Bool,
        onFlush: @escaping @MainActor (String) -> Void
    ) async {
        guard var session = sessions[msgID], !session.buffer.isEmpty else { return }
        let raw = session.buffer
        session.buffer = ""

        let toProcess: String
        if isFinal {
            toProcess = raw
        } else {
            let split = Self.splitRetainTrailingIncompleteHeadingMarkdown(raw)
            session.buffer = split.retain
            toProcess = split.toProcess
        }

        sessions[msgID] = session
        guard !toProcess.isEmpty else { return }
        onFlush(toProcess)
    }

    /// Avoid flashing broken `#` headings mid-stream when coalescing answer text.
    private static func splitRetainTrailingIncompleteHeadingMarkdown(_ full: String) -> (toProcess: String, retain: String) {
        guard !full.isEmpty else { return ("", "") }
        var hashRunStart = full.endIndex
        var scan = full.endIndex
        var hashCount = 0
        while hashCount < 6, scan > full.startIndex {
            let prev = full.index(before: scan)
            guard full[prev] == "#" else { break }
            hashRunStart = prev
            scan = prev
            hashCount += 1
        }
        guard hashCount >= 1 else { return (full, "") }
        guard hashRunStart == full.startIndex || full[full.index(before: hashRunStart)].isNewline else {
            return (full, "")
        }
        let head = String(full[..<hashRunStart])
        let tail = String(full[hashRunStart..<full.endIndex])
        return (head, tail)
    }
}
