import Foundation

/// Bundle identifiers, mach service names, and runtime paths for Citadel processes.
public enum AppConstants {
    public static let bundleIdGUI = "com.citadel.firewall"
    public static let bundleIdHelper = "com.citadel.firewall.helper"
    public static let bundleIdNetExt = "com.citadel.firewall.netext"
    public static let xpcMachServiceName = "com.citadel.firewall.helper"
    public static let ipcMachServiceName = "group.com.citadel.firewall.ipc"
    public static let appGroup = "group.com.citadel.firewall"
    public static let teamID = "group"
    public static let version = "0.1.0"
    public static let dnsProxyPort: UInt16 = 53
    public static let defaultDoHUpstream = "https://cloudflare-dns.com/dns-query"

    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Citadel", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static var sharedDataDir: URL {
        URL(fileURLWithPath: "/Library/Application Support/Citadel", isDirectory: true)
    }
}
