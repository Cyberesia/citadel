import Foundation

enum PFCommandExecutor {
    enum Failure: LocalizedError {
        case nonZeroExit(command: String, code: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case let .nonZeroExit(command, code, stderr):
                return "\(command) exited \(code): \(stderr)"
            }
        }
    }

    @discardableResult
    static func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let command = ([executable] + arguments).joined(separator: " ")
            CitadelLog.error(CitadelLog.pf, "\(command) failed: \(errText)")
            throw Failure.nonZeroExit(command: command, code: process.terminationStatus, stderr: errText.isEmpty ? outText : errText)
        }

        return outText
    }
}
