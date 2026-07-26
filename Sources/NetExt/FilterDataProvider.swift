//
//  FilterDataProvider.swift
//  Citadel Network System Extension
//
//  Citadel-native NEFilterDataProvider. Evaluates each new socket flow with
//  FirewallRuleEvaluator against the SharedRuleBridge snapshot. Ask flows are
//  paused and resolved via IPCConnection to the GUI.
//

#if canImport(NetworkExtension)
import NetworkExtension
import Foundation
import Darwin

final class FilterDataProvider: NEFilterDataProvider {
    private let evaluator = FirewallRuleEvaluator()
    private var snapshot = SharedRuleBridge.Snapshot(mode: .alert, rules: [])
    private var reloadTimer: DispatchSourceTimer?
    private let workQueue = DispatchQueue(label: "com.citadel.firewall.netext.work")
    private let askTimeout: TimeInterval = 60

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        IPCConnection.shared.startListener()
        reloadSnapshot()
        startSnapshotPoll()
        let settings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(settings) { error in completionHandler(error) }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        reloadTimer?.cancel()
        reloadTimer = nil
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow else { return .allow() }
        let connection = makeConnection(from: socketFlow)
        switch evaluator.decision(for: connection, rules: snapshot.rules, defaultMode: snapshot.mode) {
        case .allow:
            return .allow()
        case .deny:
            return .drop()
        case .ask:
            askUser(flow: flow, connection: connection)
            return .pause()
        }
    }

    // MARK: - Ask

    private func askUser(flow: NEFilterFlow, connection: Connection) {
        guard let data = try? JSONEncoder().encode(connection) else {
            resumeFlow(flow, with: NEFilterNewFlowVerdict.allow())
            return
        }

        var settled = false
        let lock = NSLock()
        let finish: (NEFilterNewFlowVerdict) -> Void = { [weak self] verdict in
            lock.lock(); defer { lock.unlock() }
            guard let self, !settled else { return }
            settled = true
            self.resumeFlow(flow, with: verdict)
        }

        let delivered = IPCConnection.shared.promptUser(flowJSON: data) { allow, _ in
            finish(allow ? .allow() : .drop())
        }
        if !delivered {
            // Fail open only when GUI is offline (cannot ask).
            finish(.allow())
            return
        }
        let denyOnTimeout = SharedAskPolicyBridge.read().timeoutDeny
        workQueue.asyncAfter(deadline: .now() + askTimeout) {
            finish(denyOnTimeout ? .drop() : .allow())
        }
    }

    // MARK: - Flow mapping

    private func makeConnection(from flow: NEFilterSocketFlow) -> Connection {
        let endpoint = flow.remoteEndpoint as? NWHostEndpoint
        let host = endpoint?.hostname ?? ""
        let port = Int(endpoint?.port ?? "0") ?? 0
        let pid = flow.sourceAppAuditToken.flatMap(pidFromAuditToken) ?? 0
        let path = pid > 0 ? executablePath(for: pid) : ""
        let name = path.isEmpty ? "Unknown" : (path as NSString).lastPathComponent
        let signing = ProcessSigningIdentity.resolve(path: path)
        return Connection(
            pid: Int32(pid),
            processName: name,
            processPath: path,
            processBundleId: bundleIdentifier(forExecutable: path),
            codeTeamID: signing.teamID,
            signingStatus: signing.status,
            remoteHost: host,
            remoteIP: host,
            remotePort: port,
            direction: flow.direction == .outbound ? .outgoing : .incoming,
            status: .pending
        )
    }

    private func pidFromAuditToken(_ data: Data) -> Int? {
        guard data.count >= MemoryLayout<audit_token_t>.size else { return nil }
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { data.copyBytes(to: $0, count: $0.count) }
        return Int(token.val.5)
    }

    private func executablePath(for pid: Int) -> String {
        let maxSize = 4096
        var buf = [CChar](repeating: 0, count: maxSize)
        let n = proc_pidpath(Int32(pid), &buf, UInt32(maxSize))
        return n > 0 ? String(cString: buf) : ""
    }

    private func bundleIdentifier(forExecutable path: String) -> String? {
        guard !path.isEmpty, let range = path.range(of: ".app/", options: .backwards) else { return nil }
        let appPath = String(path[..<range.upperBound])
        let plist = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plist)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    // MARK: - Snapshot

    private func reloadSnapshot() {
        snapshot = SharedRuleBridge.read()
    }

    private func startSnapshotPoll() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 2, repeating: .seconds(2))
        timer.setEventHandler { [weak self] in self?.reloadSnapshot() }
        timer.resume()
        reloadTimer = timer
    }
}
#endif
