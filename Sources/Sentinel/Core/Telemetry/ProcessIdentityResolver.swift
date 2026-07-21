import Foundation
import Darwin

/// Resolves PID → ProcessIdentity with family grouping heuristics.
public final class ProcessIdentityResolver: @unchecked Sendable {
    private var cache: [pid_t: ProcessIdentity] = [:]
    private let lock = NSLock()

    private static let agentNames: Set<String> = ["coworkcore", "aioncore"]
    private static let systemPrefixes = ["/usr/", "/System/", "/sbin/", "/bin/"]

    public init() {}

    public func clearCache() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }

    public func resolve(pid: pid_t, fallbackName: String = "") -> ProcessIdentity {
        lock.lock()
        if let cached = cache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let path = Self.path(for: pid)
        let name = fallbackName.isEmpty ? Self.name(for: pid, path: path) : fallbackName
        let ppid = Self.parentPID(for: pid)
        let bundleID = Self.bundleID(forPath: path)
        let (familyID, familyName) = Self.family(name: name, path: path, bundleID: bundleID)
        let role = Self.role(name: name, path: path, familyName: familyName)

        let identity = ProcessIdentity(
            pid: pid,
            ppid: ppid,
            name: name,
            path: path,
            bundleID: bundleID,
            familyID: familyID,
            familyName: familyName,
            role: role
        )

        lock.lock()
        cache[pid] = identity
        lock.unlock()
        return identity
    }

    public func resolveBatch(pids: [(pid_t, String)]) -> [pid_t: ProcessIdentity] {
        var result: [pid_t: ProcessIdentity] = [:]
        for (pid, name) in pids {
            result[pid] = resolve(pid: pid, fallbackName: name)
        }
        return result
    }

    // MARK: - System helpers

    private static func path(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
        guard result > 0 else { return "" }
        return String(cString: buffer)
    }

    private static func name(for pid: pid_t, path: String) -> String {
        if !path.isEmpty {
            let base = (path as NSString).lastPathComponent
            if !base.isEmpty { return base }
        }
        var nameBuf = [CChar](repeating: 0, count: 256)
        let ok = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        if ok > 0 {
            return String(cString: nameBuf)
        }
        return "pid-\(pid)"
    }

    private static func parentPID(for pid: pid_t) -> pid_t? {
        // Optional enrichment — family grouping primarily uses path/bundle heuristics.
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, size)
        }
        guard result > 0 else { return nil }
        let ppid = pid_t(info.pbi_ppid)
        return ppid > 0 ? ppid : nil
    }

    private static func bundleID(forPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var p = path
        if let r = p.range(of: ".app/", options: .backwards) {
            p = String(p[..<r.upperBound])
        } else if p.hasSuffix(".app") {
            // already an app bundle
        } else {
            return nil
        }
        let plist = (p as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plist)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    private static func family(name: String, path: String, bundleID: String?) -> (String, String) {
        // Prefer owning .app name from path — strongest signal for helpers.
        if let appName = appNameFromPath(path) {
            let familyID: String
            if let bid = bundleID, !bid.isEmpty {
                familyID = stripHelperBundle(bid)
            } else {
                familyID = appName.lowercased()
            }
            return (familyID, appName)
        }

        if let bid = bundleID, !bid.isEmpty {
            let familyID = stripHelperBundle(bid)
            let display = humanizeBundle(familyID)
            return (familyID, display)
        }

        let normalized = normalizeProcessFamilyName(name)
        return (normalized.lowercased(), normalized)
    }

    /// Collapse helper/plugin bundle IDs toward the parent app id.
    private static func stripHelperBundle(_ bid: String) -> String {
        var parts = bid.split(separator: ".").map(String.init)
        let helperTokens: Set<String> = [
            "helper", "helpers", "gpu", "renderer", "plugin", "xpc",
            "webview", "extension", "extensions", "module"
        ]
        while parts.count > 2,
              let last = parts.last?.lowercased(),
              helperTokens.contains(last) || last.hasSuffix("helper") {
            parts.removeLast()
        }
        return parts.joined(separator: ".")
    }

    /// "Cursor Helper (Plugin)" → "Cursor", "Microsoft Teams WebView" → "Microsoft Teams"
    private static func normalizeProcessFamilyName(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop parenthetical role: (Plugin), (Renderer), (GPU)…
        if let open = n.lastIndex(of: "(") {
            n = String(n[..<open]).trimmingCharacters(in: .whitespaces)
        }

        let suffixes = [
            " Helper", "Helper",
            " Renderer", "Renderer",
            " GPU", "GPU",
            " Network", "Networking",
            " WebView", "WebView",
            " Module", "Module",
            " Plugin", "Plugin",
            " Extension", "Extension",
        ]
        var changed = true
        while changed {
            changed = false
            for s in suffixes where n.hasSuffix(s) {
                n = String(n.dropLast(s.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        return n.isEmpty ? name : n
    }

    private static func appNameFromPath(_ path: String) -> String? {
        // Prefer outermost .app (Cursor.app/…/Helper.app → Cursor)
        guard let range = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards) else {
            return nil
        }
        let before = path[..<range.lowerBound]
        let component = (String(before) as NSString).lastPathComponent
        return component.isEmpty ? nil : component
    }

    private static func humanizeBundle(_ bid: String) -> String {
        bid.split(separator: ".").last.map(String.init)?.capitalized ?? bid
    }

    private static func role(name: String, path: String, familyName: String) -> ProcessRole {
        let lower = name.lowercased()
        let pathLower = path.lowercased()
        if agentNames.contains(lower) || pathLower.contains("coworkcore") || pathLower.contains("aioncore") {
            return .agent
        }
        // Chromium embeds role in helper .app path even when process name is generic.
        if pathLower.contains("helper (renderer)") || pathLower.contains("(renderer).app")
            || lower.contains("renderer") || lower.contains("(renderer)") {
            return .renderer
        }
        if pathLower.contains("helper (gpu)") || pathLower.contains("(gpu).app")
            || lower.contains("gpu") || lower.contains("(gpu)") {
            return .gpu
        }
        if pathLower.contains("helper (network)") || pathLower.contains("(network).app")
            || lower.contains("network") || lower.contains("networking") {
            return .network
        }
        if lower.contains("webview") { return .helper }
        if lower.contains("plugin") || lower.contains("helper")
            || pathLower.contains("/helpers/")
            || pathLower.contains("helper.app")
            || pathLower.contains("helper (") {
            return .helper
        }
        if name.caseInsensitiveCompare(familyName) == .orderedSame { return .main }
        if pathLower.contains(".app/contents/macos/") && !pathLower.contains("helper") {
            return .main
        }
        return .unknown
    }

    public static func isSystemProcess(path: String) -> Bool {
        systemPrefixes.contains { path.hasPrefix($0) }
    }
}

// Darwin proc APIs
@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ buffersize: UInt32) -> Int32

@_silgen_name("proc_name")
private func proc_name(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ buffersize: UInt32) -> Int32

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

private let PROC_PIDTBSDINFO: Int32 = 3

/// Minimal subset of `proc_bsdinfo` — only `pbi_ppid` is read.
private struct proc_bsdinfo {
    var pbi_flags: UInt32 = 0
    var pbi_status: UInt32 = 0
    var pbi_xstatus: UInt32 = 0
    var pbi_pid: UInt32 = 0
    var pbi_ppid: UInt32 = 0
    var pad: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}
