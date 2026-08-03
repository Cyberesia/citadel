import Foundation
import Darwin

/// Runtime status of the bundled CoworkCore backend process.
public enum CoworkCoreStatus: String, Sendable {
    case stopped
    case starting
    case running
    case failed
}

/// Spawns and supervises the CoworkCore backend binary bundled with Citadel.
@MainActor
public final class CoworkCoreLifecycle: ObservableObject {
    @Published public private(set) var status: CoworkCoreStatus = .stopped
    @Published public private(set) var port: Int?
    @Published public private(set) var lastError: String?
    /// When true the backend listens on 0.0.0.0 with authentication enabled (WebUI remote mode).
    @Published public private(set) var isRemoteMode = false

    private var process: Process?
    private let defaultPort = 13_400

    public init() {}

    public static let bundledBinaryName = "coworkcore"
    public static let bundledDirectoryName = "coworkcore-bundled"

    /// Restarts the backend in local (loopback, no auth) or remote (LAN, auth) mode.
    public func restart(remote: Bool) async {
        stop()
        isRemoteMode = remote
        await start()
    }

    public func start() async {
        guard status != .running, status != .starting else { return }
        status = .starting
        lastError = nil

        guard let binaryURL = resolveBinaryURL() else {
            status = .failed
            lastError = "CoworkCore binary not found in app bundle."
            return
        }

        guard let assignedPort = findAvailablePort(startingAt: defaultPort) else {
            status = .failed
            lastError = "No available port for CoworkCore."
            return
        }
        port = assignedPort

        do {
            let dataDir = try ensureDataDirectory()
            try spawnProcess(binaryURL: binaryURL, port: assignedPort, dataDir: dataDir)
            let healthy = await waitForHealth(port: assignedPort, attempts: 60)
            if healthy {
                status = .running
            } else {
                status = .failed
                lastError = "CoworkCore did not become healthy in time."
                stop()
            }
        } catch {
            status = .failed
            lastError = error.localizedDescription
            stop()
        }
    }

    public func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        port = nil
        if status != .failed {
            status = .stopped
        }
    }

    private static var runtimeKey: String {
        #if arch(arm64)
        return "darwin-arm64"
        #else
        return "darwin-x64"
        #endif
    }

    private func resolveBinaryURL() -> URL? {
        if let bundled = bundledBinaryURL(), FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let devCandidates = [
            "/usr/local/bin/coworkcore",
            "\(NSHomeDirectory())/.cargo/bin/aioncore",
            "/opt/homebrew/bin/aioncore",
            "/usr/local/bin/aioncore",
        ]
        for path in devCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func bundledBinaryURL() -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("\(Self.bundledDirectoryName)/\(Self.runtimeKey)/\(Self.bundledBinaryName)")
    }

    private func bundledRuntimeDirectory() -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("\(Self.bundledDirectoryName)/\(Self.runtimeKey)")
    }

    private func ensureDataDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Citadel/CoworkCore", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func spawnProcess(binaryURL: URL, port: Int, dataDir: URL) throws {
        let proc = Process()
        proc.executableURL = binaryURL
        var args = [
            "--port", String(port),
            "--data-dir", dataDir.path,
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier),
            "--log-level", "info",
            "--app-version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            "--managed-resources-mode", "bundled",
        ]
        if isRemoteMode {
            // Remote/WebUI mode: bind all interfaces and keep authentication on.
            args += ["--host", "0.0.0.0"]
        } else {
            args.append("--local")
        }
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        if let runtimeDir = bundledRuntimeDirectory() {
            env["AIONUI_CACHE_DIR"] = dataDir.appendingPathComponent("cache").path
            env["AIONUI_WORK_DIR"] = dataDir.appendingPathComponent("work").path
            env["AIONUI_LOG_DIR"] = dataDir.appendingPathComponent("logs").path
            try? FileManager.default.createDirectory(atPath: env["AIONUI_CACHE_DIR"]!, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(atPath: env["AIONUI_WORK_DIR"]!, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(atPath: env["AIONUI_LOG_DIR"]!, withIntermediateDirectories: true)
            // CoworkCore resolves managed-resources adjacent to the binary in bundled mode.
            _ = runtimeDir
        }
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        process = proc
    }

    private func waitForHealth(port: Int, attempts: Int) async -> Bool {
        let client = CoworkCoreClient(port: port)
        for _ in 0..<attempts {
            if await client.isHealthy() { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func findAvailablePort(startingAt: Int, attempts: Int = 40) -> Int? {
        for candidate in startingAt..<(startingAt + attempts) where isPortAvailable(candidate) {
            return candidate
        }
        return nil
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
