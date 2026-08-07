import Foundation
import os.log

/// Unified os_log categories for Citadel daemon, DNS, and packet-filter subsystems.
public enum CitadelLog {
    public static let app = OSLog(subsystem: "com.citadel.firewall", category: "app")
    public static let helper = OSLog(subsystem: "com.citadel.firewall", category: "helper")
    public static let dns = OSLog(subsystem: "com.citadel.firewall", category: "dns")
    public static let pf = OSLog(subsystem: "com.citadel.firewall", category: "pf")
    public static let netmon = OSLog(subsystem: "com.citadel.firewall", category: "netmon")

    public static func info(_ log: OSLog, _ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
    }

    public static func error(_ log: OSLog, _ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
    }

    public static func debug(_ log: OSLog, _ message: String) {
        os_log("%{public}@", log: log, type: .debug, message)
    }
}
