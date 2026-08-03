import Foundation

/// Reads and writes Codable payloads in the Citadel app-group container.
struct AppGroupJSONStore<Value: Codable> {
    private let fileName: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileName: String) {
        self.fileName = fileName
    }

    var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)?
            .appendingPathComponent(fileName)
    }

    func read(default defaultValue: Value) -> Value {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(Value.self, from: data) else {
            return defaultValue
        }
        return decoded
    }

    func write(_ value: Value) {
        guard let url = fileURL,
              let data = try? encoder.encode(value) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
