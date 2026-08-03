import Foundation

enum CoworkMLXBridgeError: LocalizedError {
    case mlxNotInstalled
    case mlxInstallFailed
    case unsupportedArchitecture
    case pythonMissing
    case invalidModelID
    case modelNotInstalled
    case serverStartFailed(String)
    case commandFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .mlxNotInstalled:
            return "On-device MLX is unavailable on this Mac."
        case .mlxInstallFailed:
            return "Failed to set up on-device MLX."
        case .unsupportedArchitecture:
            return "Native MLX requires Apple Silicon."
        case .pythonMissing:
            return "Python 3 is required for the MLX fallback runtime."
        case .invalidModelID:
            return "MLX model id is empty."
        case .modelNotInstalled:
            return "MLX model weights are missing or incomplete. Download the model first."
        case .serverStartFailed(let detail):
            return "Could not start MLX server: \(detail)"
        case .commandFailed(let command, let output):
            let tail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty {
                return "Command failed: \(command)"
            }
            return "Command failed: \(command)\n\(tail)"
        }
    }
}
