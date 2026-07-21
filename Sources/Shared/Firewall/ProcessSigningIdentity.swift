import Foundation
import Security

/// Code-signing status for a process binary (Team ID + validity).
public enum ProcessSigningStatus: String, Codable, Sendable, Hashable {
    case signedValid
    case signedInvalid
    case unsigned
    case unknown
}

/// Resolves signing identity via Security.framework for an on-disk executable path.
public enum ProcessSigningIdentity {
    public struct Snapshot: Hashable, Sendable {
        public let teamID: String?
        public let status: ProcessSigningStatus
        public let signingID: String?

        public init(teamID: String?, status: ProcessSigningStatus, signingID: String? = nil) {
            self.teamID = teamID
            self.status = status
            self.signingID = signingID
        }

        public static let unknown = Snapshot(teamID: nil, status: .unknown)
    }

    private static let cacheLock = NSLock()
    private static var pathCache: [String: Snapshot] = [:]

    public static func resolve(path: String) -> Snapshot {
        guard !path.isEmpty else { return .unknown }
        cacheLock.lock()
        if let cached = pathCache[path] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let snapshot = inspect(path: path)
        cacheLock.lock()
        pathCache[path] = snapshot
        if pathCache.count > 2048 {
            pathCache.removeAll(keepingCapacity: true)
        }
        cacheLock.unlock()
        return snapshot
    }

    public static func clearCache() {
        cacheLock.lock()
        pathCache.removeAll()
        cacheLock.unlock()
    }

    private static func inspect(path: String) -> Snapshot {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        let createStatus = SecStaticCodeCreateWithPath(url, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            return Snapshot(teamID: nil, status: .unsigned)
        }

        var error: Unmanaged<CFError>?
        let check = SecStaticCodeCheckValidityWithErrors(code, [], nil, &error)
        let valid = check == errSecSuccess

        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard infoStatus == errSecSuccess, let dict = info as? [String: Any] else {
            return Snapshot(teamID: nil, status: valid ? .signedValid : .unsigned)
        }

        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let signingID = dict[kSecCodeInfoIdentifier as String] as? String
        if team == nil, signingID == nil, !valid {
            return Snapshot(teamID: nil, status: .unsigned)
        }
        return Snapshot(
            teamID: team,
            status: valid ? .signedValid : .signedInvalid,
            signingID: signingID
        )
    }
}
