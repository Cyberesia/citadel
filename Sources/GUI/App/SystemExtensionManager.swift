import Foundation
import SystemExtensions
import NetworkExtension
import os.log

/// Activates the embedded Network System Extension and wires ask-flow IPC into AppState.
@MainActor
final class SystemExtensionManager: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case activating
        case needsApproval
        case active
        case unsupported
        case failed(String)
    }

    @Published var status: Status = .idle

    private weak var state: AppState?
    private let extensionIdentifier = AppConstants.bundleIdNetExt
    private let log = OSLog(subsystem: AppConstants.bundleIdGUI, category: "sysext")
    private var bridge: AppCommunicationBridge?

    init(state: AppState) {
        self.state = state
        super.init()
        publish()
    }

    private var hasEmbeddedExtension: Bool {
        let dir = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }
        return urls.contains { $0.pathExtension == "systemextension" }
    }

    func activate() {
        guard hasEmbeddedExtension else {
            status = .unsupported
            publish()
            state?.appendLog(
                level: "info",
                message: "Network filter not embedded — Fortress runs in local observation mode."
            )
            return
        }
        status = .activating
        publish()
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivate() {
        disableFilter()
        guard hasEmbeddedExtension else { return }
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func publish() {
        guard let state else { return }
        switch status {
        case .idle:
            state.netExtStatus = .inactive
        case .activating:
            state.netExtStatus = .activating
        case .needsApproval:
            state.netExtStatus = .needsApproval
        case .active:
            state.netExtStatus = .active
        case .unsupported:
            state.netExtStatus = .unsupported
        case .failed:
            state.netExtStatus = .failed
        }
    }

    private func enableFilter() {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] loadError in
            DispatchQueue.main.async {
                guard let self else { return }
                if let loadError {
                    self.fail("filter load: \(loadError.localizedDescription)")
                    return
                }
                if manager.providerConfiguration == nil {
                    let configuration = NEFilterProviderConfiguration()
                    configuration.filterSockets = true
                    configuration.filterPackets = false
                    manager.providerConfiguration = configuration
                    manager.localizedDescription = "Citadel"
                }
                manager.isEnabled = true
                manager.saveToPreferences { saveError in
                    DispatchQueue.main.async {
                        if let saveError {
                            self.fail("filter save: \(saveError.localizedDescription)")
                            return
                        }
                        self.status = .active
                        self.publish()
                        self.state?.appendLog(level: "info", message: "Per-app network filter active.")
                        self.registerIPC()
                    }
                }
            }
        }
    }

    private func disableFilter() {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            guard error == nil else { return }
            manager.isEnabled = false
            manager.saveToPreferences { _ in }
            DispatchQueue.main.async {
                self?.status = .idle
                self?.publish()
            }
        }
    }

    private func registerIPC() {
        guard let state else { return }
        let bridge = AppCommunicationBridge(state: state)
        self.bridge = bridge
        IPCConnection.shared.register(delegate: bridge) { ok in
            DispatchQueue.main.async {
                state.appendLog(
                    level: ok ? "info" : "error",
                    message: ok ? "Connected to network filter." : "Filter IPC unavailable."
                )
            }
        }
    }

    private func fail(_ message: String) {
        status = .failed(message)
        publish()
        state?.appendLog(level: "error", message: message)
        os_log("%{public}@", log: log, type: .error, message)
    }
}

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        Task { @MainActor in
            if result == .completed {
                enableFilter()
            } else {
                state?.appendLog(level: "info", message: "Network filter finishes after reboot.")
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in fail("Extension activation failed: \(error.localizedDescription)") }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            status = .needsApproval
            publish()
            state?.appendLog(
                level: "info",
                message: "Approve Citadel in System Settings > Privacy & Security, then it will start filtering."
            )
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }
}

/// Extension → app ask bridge (allow, remember).
final class AppCommunicationBridge: NSObject, AppCommunication {
    private weak var state: AppState?
    init(state: AppState) { self.state = state }

    func promptUser(flowJSON: Data, responseHandler: @escaping (Bool, Bool) -> Void) {
        guard let connection = try? JSONDecoder().decode(Connection.self, from: flowJSON) else {
            responseHandler(true, false)
            return
        }
        Task { @MainActor in
            guard let state else { responseHandler(true, false); return }
            state.presentAlert(for: connection, reply: responseHandler)
        }
    }
}
