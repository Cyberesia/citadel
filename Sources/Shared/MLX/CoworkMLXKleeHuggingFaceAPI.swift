import Foundation

enum CoworkMLXKleeHuggingFaceAPI {
    private static let requiredExtensions: Set<String> = [
        ".safetensors", ".json", ".txt", ".py", ".jinja", ".model", ".tiktoken",
    ]

    private static let requiredFileNames: Set<String> = [
        "config.json", "tokenizer.json", "tokenizer_config.json",
        "preprocessor_config.json", "processor_config.json",
        "video_preprocessor_config.json", "vocab.json", "merges.txt",
        "special_tokens_map.json", "generation_config.json",
        "chat_template.json", "added_tokens.json", "tokenizer.model",
    ]

    private static let excludedPatterns: [String] = [
        "README.md", "LICENSE", ".gitattributes", ".gitignore",
        "original/", "onnx/", "flax_model", "tf_model", "pytorch_model",
        "model.bin", "consolidated",
    ]

    static func resolvedEndpoint() -> String {
        if let endpoint = ProcessInfo.processInfo.environment["HF_ENDPOINT"], !endpoint.isEmpty {
            return endpoint
        }
        return "https://huggingface.co"
    }

    static func fetchFileList(modelID: String, path: String? = nil) async throws -> [CoworkMLXKleeHFFileEntry] {
        let endpoint = resolvedEndpoint()
        let suffix = path.map { "/\($0)" } ?? ""
        let urlString = "\(endpoint)/api/models/\(modelID)/tree/main\(suffix)"
        guard let url = URL(string: urlString) else {
            throw CoworkMLXKleeDownloadError.failed("Invalid Hugging Face API URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CoworkMLXKleeDownloadError.failed("Invalid Hugging Face API response")
        }
        guard http.statusCode == 200 else {
            throw CoworkMLXKleeDownloadError.failed("Hugging Face API returned HTTP \(http.statusCode)")
        }

        let entries = try JSONDecoder().decode([CoworkMLXKleeHFFileEntry].self, from: data)
        var files = entries.filter { $0.type == "file" }
        for directory in entries where directory.type == "directory" {
            let subPath = path.map { "\($0)/\(directory.path)" } ?? directory.path
            files.append(contentsOf: try await fetchFileList(modelID: modelID, path: subPath))
        }
        return files
    }

    static func filterFiles(_ files: [CoworkMLXKleeHFFileEntry]) -> [CoworkMLXKleeHFFileEntry] {
        files.filter { file in
            let name = (file.path as NSString).lastPathComponent
            let lower = file.path.lowercased()
            if excludedPatterns.contains(where: { lower.contains($0.lowercased()) }) {
                return false
            }
            if requiredFileNames.contains(name) { return true }
            return requiredExtensions.contains { name.hasSuffix($0) }
        }
    }
}
