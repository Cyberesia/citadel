import Foundation

/// Tracks in-flight interactive DNS decisions keyed by queried domain.
final class PendingDNSAskQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [String: (Bool) -> Void] = [:]

    func enqueue(domain: String, callback: @escaping (Bool) -> Void) {
        lock.lock()
        callbacks[domain] = callback
        lock.unlock()
    }

    func complete(domain: String, allowed: Bool) {
        lock.lock()
        let callback = callbacks.removeValue(forKey: domain)
        lock.unlock()
        callback?(allowed)
    }
}
