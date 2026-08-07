import Foundation

/// Rich metadata for cloud models discovered via BYOK providers.
struct CoworkDiscoveredModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let provider: String
    var description: String?
    var contextLength: Int?
    var inputPricePerMillion: Double?
    var outputPricePerMillion: Double?

    var pricingSummary: String? {
        guard let inputPricePerMillion, let outputPricePerMillion else { return nil }
        return String(format: "$%.2f / $%.2f per 1M", inputPricePerMillion, outputPricePerMillion)
    }
}

/// Enriches bare model ids returned by CoworkCore with human labels and context hints.
enum CoworkCloudModelCatalog {
    static func fromOptions(_ options: [CoworkModelOption], platform: String) -> [CoworkDiscoveredModel] {
        options.map { enrich($0, platform: platform) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func enrich(_ option: CoworkModelOption, platform: String) -> CoworkDiscoveredModel {
        let id = option.id
        let display = option.label
        let lower = id.lowercased()
        let provider = platform.lowercased()

        var description: String?
        var context = contextLength(for: lower)
        var pricing: (Double, Double)?

        switch provider {
        case "anthropic":
            description = anthropicDescription(for: lower, display: display)
            pricing = anthropicPricing(for: lower)
        case "openai":
            description = "OpenAI \(display)"
            pricing = openAIPricing(for: lower)
        case "xai":
            description = "xAI \(display)"
            context = context ?? grokContext(for: lower)
        case "infomaniak":
            description = "Infomaniak kAI \(display)"
        case "gemini", "google":
            description = "Google \(display)"
            context = context ?? geminiContext(for: lower)
        default:
            description = display == id ? nil : display
        }

        return CoworkDiscoveredModel(
            id: id,
            name: display,
            provider: provider,
            description: description,
            contextLength: context,
            inputPricePerMillion: pricing?.0,
            outputPricePerMillion: pricing?.1
        )
    }

    private static func contextLength(for id: String) -> Int? {
        if id.contains("gpt-4o") || id.contains("gpt-4-turbo") { return 128_000 }
        if id.contains("gpt-4") { return 8_192 }
        if id.contains("gpt-3.5") { return 16_384 }
        if id.contains("gpt-5") || id.contains("o1") || id.contains("o3") || id.contains("o4") { return 200_000 }
        if id.contains("claude") { return 200_000 }
        if id.contains("gemini-2.5") || id.contains("gemini-3") { return 1_048_576 }
        if id.contains("gemini") { return 1_048_576 }
        if id.contains("grok") { return grokContext(for: id) }
        return nil
    }

    private static func grokContext(for id: String) -> Int {
        if id.contains("grok-4") { return 2_000_000 }
        if id.contains("grok-3") { return 128_000 }
        return 128_000
    }

    private static func geminiContext(for id: String) -> Int {
        if id.contains("gemini-2.5") || id.contains("gemini-3") { return 1_048_576 }
        return 1_048_576
    }

    private static func anthropicDescription(for id: String, display: String) -> String {
        if id.contains("sonnet-4-5") || id.contains("sonnet-4.5") {
            return "Smart model for complex agents and coding."
        }
        if id.contains("haiku-4-5") || id.contains("haiku-4.5") {
            return "Fastest model with near-frontier intelligence."
        }
        if id.contains("opus-4-5") || id.contains("opus-4.5") {
            return "Premium model with maximum intelligence."
        }
        return display != id ? "\(display) (\(id))" : id
    }

    private static func anthropicPricing(for id: String) -> (Double, Double)? {
        if id.contains("haiku-4-5") || id.contains("haiku-4.5") { return (1, 5) }
        if id.contains("sonnet-4-5") || id.contains("sonnet-4.5") { return (3, 15) }
        if id.contains("opus-4-5") || id.contains("opus-4.5") { return (5, 25) }
        if id.contains("opus") { return (15, 75) }
        if id.contains("sonnet") { return (3, 15) }
        if id.contains("haiku") { return (0.25, 1.25) }
        return nil
    }

    private static func openAIPricing(for id: String) -> (Double, Double)? {
        if id.contains("gpt-4o-mini") { return (0.15, 0.60) }
        if id.contains("gpt-4o") { return (2.5, 10) }
        if id.contains("o1") { return (15, 60) }
        return nil
    }

    static func docsURL(for preset: CoworkProviderPreset) -> URL? {
        switch preset {
        case .openAI: return URL(string: "https://platform.openai.com/docs/models")
        case .anthropic: return URL(string: "https://docs.anthropic.com/en/docs/models")
        case .gemini: return URL(string: "https://ai.google.dev/gemini-api/docs/models")
        case .xai: return URL(string: "https://docs.x.ai/docs")
        case .infomaniak: return URL(string: "https://www.infomaniak.com/en/hosting/ai-tools")
        case .openRouter: return URL(string: "https://openrouter.ai/models")
        default: return nil
        }
    }

    /// Rough USD estimate from catalog pricing (Aisance cost-breakdown hint).
    static func estimatedCostUSD(inputTokens: Int, outputTokens: Int, modelID: String) -> Double? {
        let lower = modelID.lowercased()
        let pricing = anthropicPricing(for: lower) ?? openAIPricing(for: lower)
        guard let pricing else { return nil }
        let input = Double(inputTokens) / 1_000_000 * pricing.0
        let output = Double(outputTokens) / 1_000_000 * pricing.1
        return input + output
    }
}
