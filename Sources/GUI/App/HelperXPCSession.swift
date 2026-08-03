import Foundation

/// Maintains the privileged helper XPC connection and reconnect schedule.
@MainActor
final class HelperXPCSession {
    private(set) var connection: NSXPCConnection?
    private var reconnectDelays: [TimeInterval] = [2, 5, 10]

    func connect(eventReceiver: HelperEventReceiver, onDisconnect: @escaping () -> Void) {
        let connection = NSXPCConnection(
            machServiceName: AppConstants.xpcMachServiceName,
            options: [.privileged]
        )
        connection.remoteObjectInterface = HelperXPC.helperInterface()
        connection.exportedInterface = HelperXPC.clientInterface()
        connection.exportedObject = eventReceiver
        connection.invalidationHandler = onDisconnect
        connection.interruptionHandler = onDisconnect
        connection.resume()
        self.connection = connection
    }

    var helper: HelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { _ in } as? HelperProtocol
    }

    func scheduleReconnect(_ action: @escaping () -> Void) {
        for delay in reconnectDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    }
}
