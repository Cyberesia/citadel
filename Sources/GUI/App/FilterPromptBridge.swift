import Foundation

/// Routes interactive filter prompts from CitadelNetExt into AppState alert UI.
final class FilterPromptBridge: NSObject, AppCommunication {
    private weak var state: AppState?

    init(state: AppState) {
        self.state = state
    }

    func promptUser(flowJSON: Data, responseHandler: @escaping (Bool, Bool) -> Void) {
        guard let connection = try? JSONDecoder().decode(Connection.self, from: flowJSON) else {
            responseHandler(true, false)
            return
        }
        Task { @MainActor in
            guard let state else {
                responseHandler(true, false)
                return
            }
            state.presentAlert(for: connection, reply: responseHandler)
        }
    }
}
