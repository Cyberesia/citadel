import Foundation

// MARK: - BYOK cloud providers (inspired by Aisance Polaris cloud-models-manager)

extension CoworkState {
    /// Cloud providers configured in CoworkCore (excludes local Ollama/MLX endpoints).
    var cloudProviders: [CoworkProvider] {
        providers.filter { provider in
            let base = provider.baseURL.lowercased()
            let isLocal = base.contains("127.0.0.1") || base.contains("localhost") || base.contains(":8765")
            return !isLocal
        }
    }

    /// All enabled cloud model ids (for cost-control auto-detection).
    var enabledCloudModelIDs: [String] {
        Array(Set(cloudProviders.flatMap { provider in
            (provider.enabled ?? true) ? provider.models : []
        })).sorted()
    }

    func discoverCloudModels(
        preset: CoworkProviderPreset,
        baseURL: String,
        apiKey: String,
        productId: String? = nil
    ) async throws -> (models: [CoworkDiscoveredModel], fixedBaseURL: String?) {
        // Aisance-style direct discovery first (richer metadata).
        if preset.isCloud {
            do {
                let direct = try await CoworkCloudProviderDiscovery.fetch(
                    preset: preset,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    productId: productId
                )
                if !direct.isEmpty {
                    return (direct, nil)
                }
            } catch {
                // Fall through to CoworkCore proxy.
            }
        }

        let result = try await discoverModels(preset: preset, baseURL: baseURL, apiKey: apiKey)
        let enriched = CoworkCloudModelCatalog.fromOptions(result.models, platform: preset.platform)
        return (enriched, result.fixedBaseURL)
    }

    func refreshCloudModels(for provider: CoworkProvider) async throws -> [CoworkDiscoveredModel] {
        let preset = CoworkProviderPreset.from(platform: provider.platform)
        let productId = CoworkProviderExtraConfigStore.productId(for: provider.id)

        if preset.isCloud {
            do {
                let direct = try await CoworkCloudProviderDiscovery.fetch(
                    preset: preset,
                    baseURL: provider.baseURL,
                    apiKey: provider.apiKey,
                    productId: productId
                )
                if !direct.isEmpty { return direct }
            } catch {
                // Fall through.
            }
        }

        guard let client else { throw CoworkCoreError.notConnected }
        let response = try await client.refreshProviderModels(id: provider.id)
        return CoworkCloudModelCatalog.fromOptions(response.models, platform: provider.platform)
    }

    func saveProviderModels(
        providerID: String?,
        preset: CoworkProviderPreset,
        name: String,
        baseURL: String,
        apiKey: String,
        enabledModelIDs: [String],
        resolvedBaseURL: String?,
        productId: String? = nil
    ) async throws {
        guard let client else { throw CoworkCoreError.notConnected }
        let normalized = CoworkOllamaModelsAPI.normalizedChatBaseURL(resolvedBaseURL ?? baseURL)
        let models = enabledModelIDs

        if let providerID {
            _ = try await client.updateProvider(
                id: providerID,
                CoworkUpdateProviderRequest(
                    name: name,
                    baseURL: normalized,
                    apiKey: apiKey.isEmpty ? nil : apiKey,
                    models: models,
                    enabled: true
                )
            )
            CoworkProviderExtraConfigStore.setProductId(productId, for: providerID)
        } else {
            let created = try await client.createProvider(
                CoworkCreateProviderRequest(
                    platform: preset.platform,
                    name: name,
                    baseURL: normalized,
                    apiKey: apiKey,
                    models: models,
                    enabled: true
                )
            )
            CoworkProviderExtraConfigStore.setProductId(productId, for: created.id)
        }

        providers = try await client.listProviders()
        if let first = models.first {
            if let providerID,
               let updated = providers.first(where: { $0.id == providerID }) {
                selectedProviderID = updated.id
                selectedModelID = updated.models.contains(first) ? first : updated.models.first
            } else if let created = providers.first(where: { $0.name == name && $0.baseURL == normalized }) {
                selectedProviderID = created.id
                selectedModelID = created.models.contains(first) ? first : created.models.first
            }
        }
        persistModelSelection()
    }

    func deleteProvider(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteProvider(id: id)
            CoworkProviderExtraConfigStore.remove(providerID: id)
            providers = try await client.listProviders()
            if selectedProviderID == id {
                selectedProviderID = providers.first?.id
                selectedModelID = providers.first?.models.first
                persistModelSelection()
            }
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }

    func toggleProviderEnabled(_ provider: CoworkProvider, enabled: Bool) async {
        guard let client else { return }
        do {
            _ = try await client.updateProvider(
                id: provider.id,
                CoworkUpdateProviderRequest(enabled: enabled)
            )
            providers = try await client.listProviders()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
        }
    }
}
