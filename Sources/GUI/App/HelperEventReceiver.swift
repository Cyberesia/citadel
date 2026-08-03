import Foundation

/// Receives push notifications from CitadelHelper and forwards them into AppState.
final class HelperEventReceiver: NSObject, HelperClientProtocol {
    weak var state: AppState?

    init(state: AppState?) {
        self.state = state
    }

    func notifyConnection(connectionJSON: Data) {
        guard let connections = try? JSONDecoder().decode([Connection].self, from: connectionJSON) else { return }
        Task { @MainActor in state?.updateConnections(connections) }
    }

    func notifyTraffic(sampleJSON: Data) {
        guard let sample = try? JSONDecoder().decode(TrafficSample.self, from: sampleJSON) else { return }
        Task { @MainActor in state?.appendSample(sample) }
    }

    func notifyAlert(connectionJSON: Data, reply: @escaping (Bool, Bool) -> Void) {
        guard let connection = try? JSONDecoder().decode(Connection.self, from: connectionJSON) else {
            reply(true, false)
            return
        }
        Task { @MainActor in state?.presentAlert(for: connection, reply: reply) }
    }

    func notifyLog(level: String, message: String) {
        Task { @MainActor in state?.appendLog(level: level, message: message) }
    }
}
