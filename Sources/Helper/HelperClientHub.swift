import Foundation

/// Tracks connected GUI clients and fans out helper events over XPC.
final class HelperClientHub: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []

    func attach(_ connection: NSXPCConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
    }

    func detach(_ connection: NSXPCConnection) {
        lock.lock()
        connections.removeAll { $0 === connection }
        lock.unlock()
    }

    func broadcast(_ action: (HelperClientProtocol) -> Void) {
        lock.lock()
        let snapshot = connections
        lock.unlock()

        for connection in snapshot {
            guard let client = connection.remoteObjectProxy as? HelperClientProtocol else { continue }
            action(client)
        }
    }
}
