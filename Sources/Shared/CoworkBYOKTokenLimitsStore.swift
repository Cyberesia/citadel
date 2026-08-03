import Foundation

/// BYOK output-token caps (Aisance ai-models-cost-control-settings).
struct CoworkBYOKTokenLimitsSettings: Codable, Equatable, Sendable {
    var maxOutputTokensDefault: Int?
    var maxOutputTokensByModel: [String: Int]

    static let empty = CoworkBYOKTokenLimitsSettings(maxOutputTokensDefault: nil, maxOutputTokensByModel: [:])
}

enum CoworkBYOKTokenLimitsStore {
    private static let cacheKey = "cowork.byokTokenLimits.v1"

    static func load() -> CoworkBYOKTokenLimitsSettings {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode(CoworkBYOKTokenLimitsSettings.self, from: data) else {
            return .empty
        }
        return decoded
    }

    static func save(_ settings: CoworkBYOKTokenLimitsSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    /// Aisance-style recommended caps from model id heuristics.
    static func recommendedCaps(for modelID: String) -> (fast: Int, safe: Int) {
        let id = modelID.lowercased()
        if id.contains("mini") || id.contains("flash") || id.contains("haiku")
            || id.contains("nano") || id.contains("small") {
            return (400, 800)
        }
        if id.contains("sonnet") || id.contains("pro") || id.contains("turbo")
            || id.contains("gpt-4") || id.contains("k2") || id.contains("o3")
            || id.contains("o4") || id.contains("grok") || id.contains("opus") {
            return (800, 1600)
        }
        return (600, 1200)
    }

    static func cap(for modelID: String, settings: CoworkBYOKTokenLimitsSettings) -> Int? {
        if let specific = settings.maxOutputTokensByModel[modelID], specific > 0 {
            return specific
        }
        if let defaultCap = settings.maxOutputTokensDefault, defaultCap > 0 {
            return defaultCap
        }
        return nil
    }
}
