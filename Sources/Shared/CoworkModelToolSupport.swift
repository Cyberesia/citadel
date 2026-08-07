import Foundation

/// Whether a model can run Cowork's agent tool/MCP pipeline (vs chat-only).
enum CoworkModelToolSupport {
    static func supportsTools(
        modelID: String?,
        providerID: String?,
        providers: [CoworkProvider],
        ollamaModels: [CoworkOllamaModelsAPI.OllamaModel]
    ) -> Bool {
        let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return true }

        if let ollama = ollamaModels.first(where: { $0.name == trimmed }) {
            return ollama.supportsTools
        }

        if let providerID,
           let provider = providers.first(where: { $0.id == providerID }) {
            return supportsToolsForProvider(
                platform: provider.platform,
                baseURL: provider.baseURL,
                modelID: trimmed
            )
        }

        return heuristicForModelName(trimmed)
    }

    static func supportsToolsForProvider(platform: String, baseURL: String, modelID: String) -> Bool {
        switch platform.lowercased() {
        case "openai", "anthropic", "gemini", "google":
            return true
        case "ollama", "custom":
            let lowerBase = baseURL.lowercased()
            if lowerBase.contains(":8765") || lowerBase.contains("mlx") {
                // Native MLX OpenAI shim is chat-only (no tool schemas).
                return false
            }
            if lowerBase.contains("11434") || lowerBase.contains("1234") {
                return heuristicForModelName(modelID)
            }
            return true
        default:
            return heuristicForModelName(modelID)
        }
    }

    static func heuristicForModelName(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        if lower.contains("gemma") { return false }
        if lower.contains("flux") { return false }
        if lower.contains("embed") { return false }
        if lower.contains("nomic") { return false }
        if lower.contains("apertus") { return false }
        if lower.contains("qwen") { return true }
        if lower.contains("deepseek") { return true }
        if lower.contains("mistral") || lower.contains("mixtral") { return true }
        if lower.contains("gpt") || lower.contains("claude") || lower.contains("gemini") { return true }
        if lower.contains("llama3") || lower.contains("llama-3") { return true }
        return false
    }

    /// Cloud BYOK providers need curated MCP (schema-safe subset), not a blind enable-all.
    static func prefersCuratedMcp(platform: String) -> Bool {
        switch platform.lowercased() {
        case "openai", "anthropic", "gemini", "google", "xai", "openrouter", "infomaniak", "custom":
            return true
        default:
            return false
        }
    }

    static func mcpToolProfile(platform: String) -> CoworkMcpToolProfile {
        CoworkMcpToolProfile.from(platform: platform)
    }

    @available(*, deprecated, renamed: "prefersCuratedMcp")
    static func prefersMcpOffByDefault(platform: String) -> Bool {
        prefersCuratedMcp(platform: platform)
    }
}
