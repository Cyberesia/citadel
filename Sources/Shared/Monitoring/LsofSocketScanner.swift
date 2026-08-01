import Foundation

/// Parses `lsof -F pcnT` output into established outbound TCP connections.
enum LsofSocketScanner {
    static func scanConnections() -> [Connection] {
        guard let output = runLsof() else { return [] }

        var connections: [Connection] = []
        var currentPID: Int32 = 0
        var currentName = ""

        for line in output.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPID = Int32(value) ?? 0
            case "c":
                currentName = value
            case "n":
                if let connection = parseNetworkLine(
                    value,
                    pid: currentPID,
                    processName: currentName
                ) {
                    connections.append(connection)
                }
            default:
                continue
            }
        }

        return connections
    }

    // MARK: - lsof execution

    private static func runLsof() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "-n", "-P", "-F", "pcnT"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            CitadelLog.debug(CitadelLog.netmon, "lsof unavailable: \(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Network row parsing

    private static func parseNetworkLine(
        _ line: String,
        pid: Int32,
        processName: String
    ) -> Connection? {
        guard line.contains("->") else { return nil }

        let addressToken = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? line
        let endpoints = addressToken.split(separator: "-", maxSplits: 1).map(String.init)
        guard endpoints.count == 2 else { return nil }

        let localEndpoint = endpoints[0]
        var remoteEndpoint = endpoints[1]
        if remoteEndpoint.hasPrefix(">") {
            remoteEndpoint.removeFirst()
        }

        guard let (_, localPort) = parseHostPort(localEndpoint),
              let (remoteHost, remotePort) = parseHostPort(remoteEndpoint) else {
            return nil
        }

        let executablePath = ProcessExecutableLookup.executablePath(for: pid)
        let signing = ProcessSigningIdentity.resolve(path: executablePath)

        return Connection(
            pid: pid,
            processName: processName,
            processPath: executablePath,
            processBundleId: ProcessExecutableLookup.bundleIdentifier(forExecutablePath: executablePath),
            codeTeamID: signing.teamID,
            signingStatus: signing.status,
            localPort: localPort,
            remoteHost: remoteHost,
            remoteIP: remoteHost,
            remotePort: remotePort,
            direction: .outgoing,
            status: .established,
            protocolName: "tcp"
        )
    }

    private static func parseHostPort(_ endpoint: String) -> (String, Int)? {
        if endpoint.hasPrefix("[") {
            guard let closingBracket = endpoint.firstIndex(of: "]") else { return nil }
            let host = String(endpoint[endpoint.index(after: endpoint.startIndex)..<closingBracket])
            let afterBracket = endpoint.index(after: closingBracket)
            guard afterBracket < endpoint.endIndex, endpoint[afterBracket] == ":" else { return nil }
            let portStart = endpoint.index(after: afterBracket)
            guard let port = Int(endpoint[portStart...]) else { return nil }
            return (host, port)
        }

        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        let host = String(endpoint[..<colon])
        let portText = endpoint[endpoint.index(after: colon)...]
        guard let port = Int(portText) else { return nil }
        return (host, port)
    }
}
