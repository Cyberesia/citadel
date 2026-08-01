import Foundation

/// Frozen XPC selectors between Citadel.app and CitadelHelper.
@objc public protocol HelperProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func getStatus(reply: @escaping (Data) -> Void)
    func setMode(rawValue: String, reply: @escaping (Bool, String?) -> Void)

    func reloadRules(rulesJSON: Data, reply: @escaping (Bool, String?) -> Void)
    func addRule(ruleJSON: Data, reply: @escaping (Bool, String?) -> Void)
    func removeRule(idString: String, reply: @escaping (Bool, String?) -> Void)
    func listRules(profile: String, reply: @escaping (Data) -> Void)

    func startMonitoring(reply: @escaping (Bool, String?) -> Void)
    func stopMonitoring(reply: @escaping (Bool, String?) -> Void)
    func currentConnections(reply: @escaping (Data) -> Void)
    func currentTrafficSample(reply: @escaping (Data) -> Void)

    func enableBlocklist(idString: String, enabled: Bool, reply: @escaping (Bool, String?) -> Void)
    func refreshBlocklists(reply: @escaping (Bool, String?) -> Void)
    func setDoHUpstream(url: String, reply: @escaping (Bool, String?) -> Void)
    func listBlocklists(reply: @escaping (Data) -> Void)
    func listProfiles(reply: @escaping (Data) -> Void)
    func setActiveProfile(name: String, reply: @escaping (Bool, String?) -> Void)
    func purgeExpiredRules(reply: @escaping (Bool, String?) -> Void)
    func purgeSessionRules(reply: @escaping (Bool, String?) -> Void)
    func setDNSFilterEnabled(enabled: Bool, reply: @escaping (Bool, String?) -> Void)

    func installPF(reply: @escaping (Bool, String?) -> Void)
    func uninstallPF(reply: @escaping (Bool, String?) -> Void)
    func flushAll(reply: @escaping (Bool, String?) -> Void)

    func recentBlocked(limit: Int, reply: @escaping (Data) -> Void)
    func recentDenied(limit: Int, reply: @escaping (Data) -> Void)
}

/// Push channel from CitadelHelper back into the GUI process.
@objc public protocol HelperClientProtocol {
    func notifyConnection(connectionJSON: Data)
    func notifyTraffic(sampleJSON: Data)
    func notifyAlert(connectionJSON: Data, reply: @escaping (Bool, Bool) -> Void)
    func notifyLog(level: String, message: String)
}

/// Builds the NSXPC interfaces used by the helper daemon and GUI client.
public enum HelperXPC {
    public static let machServiceName = AppConstants.xpcMachServiceName

    public static func helperInterface() -> NSXPCInterface {
        NSXPCInterface(with: HelperProtocol.self)
    }

    public static func clientInterface() -> NSXPCInterface {
        NSXPCInterface(with: HelperClientProtocol.self)
    }
}

/// Legacy alias kept for existing call sites.
public enum HelperBridge {
    public static let machServiceName = HelperXPC.machServiceName
    public static func remoteInterface() -> NSXPCInterface { HelperXPC.helperInterface() }
    public static func exportedInterface() -> NSXPCInterface { HelperXPC.clientInterface() }
}
