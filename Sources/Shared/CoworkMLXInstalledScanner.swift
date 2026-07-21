import Foundation

/// Scans disk for complete MLX model weights (Citadel cache + Hugging Face hub).
enum CoworkMLXInstalledScanner {
    struct InstalledModel: Identifiable, Hashable, Sendable {
        let id: String
        let displayName: String
        let sizeLabel: String
    }

    static func installedModels(from installedByteSizes: [String: Int64] = [:]) -> [InstalledModel] {
        let sizes = installedByteSizes.isEmpty
            ? fallbackInstalledIDs().reduce(into: [String: Int64]()) { partial, id in
                partial[id] = CoworkMLXHubCache.installedBytes(forRepoID: id)
            }
            : installedByteSizes
        return CoworkMLXModelCatalog.models.compactMap { model in
            guard (sizes[model.id] ?? 0) > 0 else { return nil }
            return InstalledModel(id: model.id, displayName: model.displayName, sizeLabel: model.sizeLabel)
        }
    }

    private static func fallbackInstalledIDs() -> [String] {
        CoworkMLXModelCatalog.models.compactMap { model in
            CoworkMLXHubCache.isRepoComplete(model.id) ? model.id : nil
        }
    }
}
