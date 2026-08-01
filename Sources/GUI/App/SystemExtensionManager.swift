import Foundation
import NetworkExtension
import SystemExtensions
import os.log

/// Orchestrates CitadelNetExt activation, filter enablement, and ask-flow IPC.
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
    private var promptBridge: FilterPromptBridge?

    init(state: AppState) {
        self.state = state
        super.init()
        syncPublishedStatus()
    }

    func activate() {
        guard embeddedExtensionExists() else {
            transition(to: .unsupported)
            state?.appendLog(
                level: "info",
                message: "Network filter not embedded — Fortress runs in local observation mode."
            )
            return
        }

        transition(to: .activating)
        submitActivationRequest()
    }

    func deactivate() {
        NEFilterConfigurator.disable()
        guard embeddedExtensionExists() else { return }
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        transition(to: .idle)
    }

    // MARK: - Private

    private func embeddedExtensionExists() -> Bool {
        let directory = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        return contents.contains { $0.pathExtension == "systemextension" }
    }

    private func submitActivationRequest() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func enableContentFilter() {
        NEFilterConfigurator.enable(localizedName: "Citadel") { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.transition(to: .active)
                    self.state?.appendLog(level: "info", message: "Per-app network filter active.")
                    self.connectPromptBridge()
                case .failure(let error):
                    self.reportFailure("filter configuration failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func connectPromptBridge() {
        guard let state else { return }
        let bridge = FilterPromptBridge(state: state)
        promptBridge = bridge
        IPCConnection.shared.register(delegate: bridge) { ok in
            Task { @MainActor in
                state.appendLog(
                    level: ok ? "info" : "error",
                    message: ok ? "Connected to network filter." : "Filter IPC unavailable."
                )
            }
        }
    }

    private func transition(to next: Status) {
        status = next
        syncPublishedStatus()
    }

    private func syncPublishedStatus() {
        guard let state else { return }
        switch status {
        case .idle: state.netExtStatus = .inactive
        case .activating: state.netExtStatus = .activating
        case .needsApproval: state.netExtStatus = .needsApproval
        case .active: state.netExtStatus = .active
        case .unsupported: state.netExtStatus = .unsupported
        case .failed: state.netExtStatus = .failed
        }
    }

    private func reportFailure(_ message: String) {
        transition(to: .failed(message))
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
                enableContentFilter()
            } else {
                state?.appendLog(level: "info", message: "Network filter finishes after reboot.")
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            reportFailure("Extension activation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            transition(to: .needsApproval)
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
