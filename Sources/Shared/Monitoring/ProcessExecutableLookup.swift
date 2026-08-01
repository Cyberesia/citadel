import Darwin
import Foundation

/// Resolves process metadata used when mapping socket rows to `Connection` records.
enum ProcessExecutableLookup {
    static func executablePath(for pid: Int32) -> String {
        guard pid > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    static func bundleIdentifier(forExecutablePath path: String) -> String? {
        guard !path.isEmpty,
              let appMarker = path.range(of: ".app/", options: .backwards) else {
            return nil
        }

        let appPath = String(path[..<appMarker.upperBound])
        let plistURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }
}
