#if canImport(NetworkExtension)
import Darwin
import Foundation
import NetworkExtension

/// Maps `NEFilterSocketFlow` objects into Citadel `Connection` telemetry records.
enum FilterSocketFlowMapper {
    static func connection(from flow: NEFilterSocketFlow) -> Connection {
        let remote = flow.remoteEndpoint as? NWHostEndpoint
        let host = remote?.hostname ?? ""
        let port = Int(remote?.port ?? "0") ?? 0
        let pid = flow.sourceAppAuditToken.flatMap(pidFromAuditToken) ?? 0
        let executablePath = pid > 0 ? ProcessExecutableLookup.executablePath(for: Int32(pid)) : ""
        let processName = executablePath.isEmpty ? "Unknown" : (executablePath as NSString).lastPathComponent
        let signing = ProcessSigningIdentity.resolve(path: executablePath)

        return Connection(
            pid: Int32(pid),
            processName: processName,
            processPath: executablePath,
            processBundleId: ProcessExecutableLookup.bundleIdentifier(forExecutablePath: executablePath),
            codeTeamID: signing.teamID,
            signingStatus: signing.status,
            remoteHost: host,
            remoteIP: host,
            remotePort: port,
            direction: flow.direction == .outbound ? .outgoing : .incoming,
            status: .pending
        )
    }

    private static func pidFromAuditToken(_ data: Data) -> Int? {
        guard data.count >= MemoryLayout<audit_token_t>.size else { return nil }
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { data.copyBytes(to: $0, count: $0.count) }
        return Int(token.val.5)
    }
}
#endif
