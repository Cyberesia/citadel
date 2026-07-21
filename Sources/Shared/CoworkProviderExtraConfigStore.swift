import Foundation

/// Local BYOK provider extras not persisted by CoworkCore (e.g. Infomaniak product_id).
enum CoworkProviderExtraConfigStore {
    private static let defaultsKey = "cowork.providerExtraConfig.v1"

    static func productId(for providerID: String) -> String? {
        let map = load()
        let value = map[providerID]?["product_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func setProductId(_ productId: String?, for providerID: String) {
        var map = load()
        var entry = map[providerID] ?? [:]
        if let productId, !productId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry["product_id"] = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            entry.removeValue(forKey: "product_id")
        }
        if entry.isEmpty {
            map.removeValue(forKey: providerID)
        } else {
            map[providerID] = entry
        }
        save(map)
    }

    static func remove(providerID: String) {
        var map = load()
        map.removeValue(forKey: providerID)
        save(map)
    }

    private static func load() -> [String: [String: String]] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save(_ map: [String: [String: String]]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
