import Foundation
import NetworkExtension

/// Configures and toggles the Citadel content-filter provider via NEFilterManager.
enum NEFilterConfigurator {
    static func enable(localizedName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { loadError in
            if let loadError {
                completion(.failure(loadError))
                return
            }

            if manager.providerConfiguration == nil {
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterPackets = false
                manager.providerConfiguration = configuration
            }
            manager.localizedDescription = localizedName
            manager.isEnabled = true
            manager.saveToPreferences { saveError in
                if let saveError {
                    completion(.failure(saveError))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    static func disable() {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { _ in
            manager.isEnabled = false
            manager.saveToPreferences { _ in }
        }
    }
}
