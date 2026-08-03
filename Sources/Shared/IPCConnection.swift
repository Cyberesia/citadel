import Foundation

/// GUI-side contract: the network filter extension calls this when a flow needs
/// an interactive decision. `responseHandler(allow, remember)`.
@objc public protocol AppCommunication {
    func promptUser(flowJSON: Data, responseHandler: @escaping (Bool, Bool) -> Void)
}

/// Extension-side contract: the GUI calls this after connecting to register itself.
@objc public protocol ProviderCommunication {
    func register(_ completionHandler: @escaping (Bool) -> Void)
}

/// Bidirectional XPC bridge between Citadel.app and CitadelNetExt.
///
/// The extension listens on `AppConstants.ipcMachServiceName`. When the GUI
/// connects it exports `AppCommunication` and imports `ProviderCommunication`.
/// Paused filter flows are resolved by calling back into the GUI over that link.
public final class IPCConnection: NSObject, @unchecked Sendable {
    public static let shared = IPCConnection()

    private let sync = NSLock()
    private var machListener: NSXPCListener?
    private var peer: NSXPCConnection?

    private override init() {
        super.init()
    }

    // MARK: - Network extension (provider)

    /// Begin vending the mach service. Call from `FilterDataProvider.startFilter`.
    public func startListener() {
        sync.lock()
        defer { sync.unlock() }

        guard machListener == nil else { return }

        let listener = NSXPCListener(machServiceName: AppConstants.ipcMachServiceName)
        listener.delegate = self
        listener.resume()
        machListener = listener
    }

    /// Ask the connected GUI to resolve a paused flow. Returns `false` when no
    /// GUI is attached — callers should fail open in that case.
    @discardableResult
    public func promptUser(flowJSON: Data, responseHandler: @escaping (Bool, Bool) -> Void) -> Bool {
        let connection = sync.withLock { peer }
        guard let connection else { return false }

        guard let app = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            self?.dropPeer()
        }) as? AppCommunication else {
            return false
        }

        app.promptUser(flowJSON: flowJSON, responseHandler: responseHandler)
        return true
    }

    // MARK: - GUI (client)

    /// Connect to the active filter extension and register `delegate` for prompts.
    public func register(delegate: AppCommunication, completionHandler: @escaping (Bool) -> Void) {
        sync.lock()
        peer?.invalidate()
        sync.unlock()

        let connection = NSXPCConnection(machServiceName: AppConstants.ipcMachServiceName, options: [])
        connection.exportedInterface = NSXPCInterface(with: AppCommunication.self)
        connection.exportedObject = delegate
        connection.remoteObjectInterface = NSXPCInterface(with: ProviderCommunication.self)
        connection.invalidationHandler = { [weak self] in self?.dropPeer() }
        connection.interruptionHandler = { [weak self] in self?.dropPeer() }

        sync.lock()
        peer = connection
        sync.unlock()

        connection.resume()

        guard let provider = connection.remoteObjectProxyWithErrorHandler({ _ in
            completionHandler(false)
        }) as? ProviderCommunication else {
            completionHandler(false)
            return
        }

        provider.register(completionHandler)
    }

    // MARK: - Lifecycle

    private func dropPeer() {
        sync.lock()
        peer = nil
        sync.unlock()
    }

    private func adoptPeer(_ connection: NSXPCConnection) {
        sync.lock()
        peer?.invalidate()
        peer = connection
        sync.unlock()
    }
}

// MARK: - NSXPCListenerDelegate

extension IPCConnection: NSXPCListenerDelegate {
    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ProviderCommunication.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: AppCommunication.self)
        newConnection.invalidationHandler = { [weak self] in self?.dropPeer() }
        newConnection.interruptionHandler = { [weak self] in self?.dropPeer() }

        adoptPeer(newConnection)
        newConnection.resume()
        return true
    }
}

// MARK: - ProviderCommunication

extension IPCConnection: ProviderCommunication {
    public func register(_ completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

// MARK: - Lock helper

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
