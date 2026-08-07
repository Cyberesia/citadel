import Foundation

struct CoworkMLXModelInfo: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let sizeLabel: String
    let minRAMGB: Int
    let expectedDownloadBytes: Int64
    let detailSubtitle: String?
    let supportsVision: Bool

    var ramRequirementLabel: String { "Requires \(minRAMGB)GB+ RAM" }
}

enum CoworkMLXModelCatalog {
    static let defaultRepoID = "mlx-community/Qwen3-4B-4bit"

    static let models: [CoworkMLXModelInfo] = [
        CoworkMLXModelInfo(
            id: "mlx-community/Qwen3-4B-4bit",
            displayName: "Cowork Small",
            sizeLabel: "~2.5 GB",
            minRAMGB: 12,
            expectedDownloadBytes: 2_500_000_000,
            detailSubtitle: "Qwen 3 4B (4-bit)",
            supportsVision: false
        ),
        CoworkMLXModelInfo(
            id: "mlx-community/Qwen3-8B-4bit",
            displayName: "Cowork Medium",
            sizeLabel: "~4.3 GB",
            minRAMGB: 16,
            expectedDownloadBytes: 4_300_000_000,
            detailSubtitle: "Qwen 3 8B",
            supportsVision: false
        ),
        CoworkMLXModelInfo(
            id: "mlx-community/Qwen3.5-9B-4bit",
            displayName: "Cowork Vision 9B",
            sizeLabel: "~6 GB",
            minRAMGB: 16,
            expectedDownloadBytes: 6_000_000_000,
            detailSubtitle: "Qwen 3.5 9B",
            supportsVision: true
        ),
        CoworkMLXModelInfo(
            id: "mlx-community/gemma-3-12b-it-qat-4bit",
            displayName: "Cowork Gemma 12B",
            sizeLabel: "~8 GB",
            minRAMGB: 16,
            expectedDownloadBytes: 8_000_000_000,
            detailSubtitle: "Gemma 3 12B",
            supportsVision: false
        ),
        CoworkMLXModelInfo(
            id: "mlx-community/Qwen3.5-27B-4bit",
            displayName: "Cowork Large",
            sizeLabel: "~16 GB",
            minRAMGB: 32,
            expectedDownloadBytes: 16_000_000_000,
            detailSubtitle: "Qwen 3.5 27B",
            supportsVision: true
        ),
        CoworkMLXModelInfo(
            id: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit",
            displayName: "Cowork Mistral",
            sizeLabel: "~14 GB",
            minRAMGB: 32,
            expectedDownloadBytes: 14_000_000_000,
            detailSubtitle: "Mistral Small 24B",
            supportsVision: false
        ),
        CoworkMLXModelInfo(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Cowork Llama",
            sizeLabel: "~2 GB",
            minRAMGB: 12,
            expectedDownloadBytes: 2_000_000_000,
            detailSubtitle: "Llama 3.2 3B",
            supportsVision: false
        ),
    ]

    static func physicalRAMGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
}
