import Foundation

/// Identifies traffic that belongs to the Cowork agent backend, so the firewall
/// side (globe, monitor, rules) can tag and control it.
public enum CitadelAgentProcess {
    public static let processNames: Set<String> = ["coworkcore", "aioncore"]

    public static func isAgent(processName: String) -> Bool {
        processNames.contains(processName.lowercased())
    }

    public static func isAgent(processName: String, processPath: String) -> Bool {
        isAgent(processName: processName) || processPath.contains("coworkcore-bundled")
    }

    public static func isAgent(_ connection: Connection) -> Bool {
        isAgent(processName: connection.processName, processPath: connection.processPath)
    }
}
