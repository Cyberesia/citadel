import Foundation
import SQLite3

enum RuleStoreRowMapping {
    static func text(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    static func optionalText(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column: column)
    }

    static func rule(from statement: OpaquePointer?) -> Rule? {
        Rule(
            id: UUID(uuidString: text(statement, column: 0)) ?? UUID(),
            processBundleId: optionalText(statement, column: 1),
            processPath: optionalText(statement, column: 2),
            processName: optionalText(statement, column: 3),
            codeTeamID: optionalText(statement, column: 20),
            requiresSignature: sqlite3_column_type(statement, 21) != SQLITE_NULL && sqlite3_column_int(statement, 21) == 1,
            remoteHost: optionalText(statement, column: 4),
            remoteIP: optionalText(statement, column: 5),
            remotePort: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6)),
            direction: RuleDirection(rawValue: text(statement, column: 7)) ?? .outgoing,
            action: RuleAction(rawValue: text(statement, column: 8)) ?? .ask,
            scope: RuleScope(rawValue: text(statement, column: 9)) ?? .domain,
            priority: Int(sqlite3_column_int(statement, 10)),
            profile: text(statement, column: 11),
            groupName: optionalText(statement, column: 12),
            notes: optionalText(statement, column: 13),
            enabled: sqlite3_column_int(statement, 14) == 1,
            temporary: sqlite3_column_int(statement, 15) == 1,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 16)),
            expiresAt: sqlite3_column_type(statement, 17) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 17)),
            lastUsedAt: sqlite3_column_type(statement, 18) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 18)),
            hitCount: Int(sqlite3_column_int(statement, 19))
        )
    }

    static func connection(from statement: OpaquePointer?) -> Connection? {
        Connection(
            id: UUID(uuidString: text(statement, column: 0)) ?? UUID(),
            pid: sqlite3_column_int(statement, 1),
            processName: text(statement, column: 2),
            processPath: text(statement, column: 3),
            processBundleId: optionalText(statement, column: 4),
            codeTeamID: optionalText(statement, column: 20),
            signingStatus: ProcessSigningStatus(rawValue: text(statement, column: 21)) ?? .unknown,
            localPort: Int(sqlite3_column_int(statement, 5)),
            remoteHost: text(statement, column: 6),
            remoteIP: text(statement, column: 7),
            remotePort: Int(sqlite3_column_int(statement, 8)),
            direction: RuleDirection(rawValue: text(statement, column: 9)) ?? .outgoing,
            status: Connection.Status(rawValue: text(statement, column: 10)) ?? .established,
            protocolName: text(statement, column: 11),
            bytesIn: sqlite3_column_int64(statement, 12),
            bytesOut: sqlite3_column_int64(statement, 13),
            country: optionalText(statement, column: 14),
            countryCode: optionalText(statement, column: 15),
            latitude: sqlite3_column_type(statement, 16) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 16),
            longitude: sqlite3_column_type(statement, 17) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 17),
            firstSeen: Date(timeIntervalSince1970: sqlite3_column_double(statement, 18)),
            lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(statement, 19))
        )
    }

    static func profile(from statement: OpaquePointer?) -> Profile? {
        Profile(
            id: UUID(uuidString: text(statement, column: 0)) ?? UUID(),
            name: text(statement, column: 1),
            mode: AppMode(rawValue: text(statement, column: 2)) ?? .alert,
            icon: text(statement, column: 3),
            isActive: sqlite3_column_int(statement, 4) == 1
        )
    }

    static func blocklist(from statement: OpaquePointer?) -> BlocklistInfo? {
        BlocklistInfo(
            id: UUID(uuidString: text(statement, column: 0)) ?? UUID(),
            name: text(statement, column: 1),
            url: text(statement, column: 2),
            enabled: sqlite3_column_int(statement, 3) == 1,
            lastUpdated: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            entryCount: Int(sqlite3_column_int(statement, 5))
        )
    }

    static func bind(rule: Rule, to statement: OpaquePointer?) {
        SQLiteHandle.bindText(statement, index: 1, value: rule.id.uuidString)
        SQLiteHandle.bindText(statement, index: 2, value: rule.processBundleId)
        SQLiteHandle.bindText(statement, index: 3, value: rule.processPath)
        SQLiteHandle.bindText(statement, index: 4, value: rule.processName)
        SQLiteHandle.bindText(statement, index: 5, value: rule.remoteHost)
        SQLiteHandle.bindText(statement, index: 6, value: rule.remoteIP)
        if let port = rule.remotePort {
            sqlite3_bind_int(statement, 7, Int32(port))
        } else {
            sqlite3_bind_null(statement, 7)
        }
        SQLiteHandle.bindText(statement, index: 8, value: rule.direction.rawValue)
        SQLiteHandle.bindText(statement, index: 9, value: rule.action.rawValue)
        SQLiteHandle.bindText(statement, index: 10, value: rule.scope.rawValue)
        sqlite3_bind_int(statement, 11, Int32(rule.priority))
        SQLiteHandle.bindText(statement, index: 12, value: rule.profile)
        SQLiteHandle.bindText(statement, index: 13, value: rule.groupName)
        SQLiteHandle.bindText(statement, index: 14, value: rule.notes)
        sqlite3_bind_int(statement, 15, rule.enabled ? 1 : 0)
        sqlite3_bind_int(statement, 16, rule.temporary ? 1 : 0)
        sqlite3_bind_double(statement, 17, rule.createdAt.timeIntervalSince1970)
        if let expires = rule.expiresAt {
            sqlite3_bind_double(statement, 18, expires.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 18)
        }
        if let lastUsed = rule.lastUsedAt {
            sqlite3_bind_double(statement, 19, lastUsed.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 19)
        }
        sqlite3_bind_int(statement, 20, Int32(rule.hitCount))
        SQLiteHandle.bindText(statement, index: 21, value: rule.codeTeamID)
        sqlite3_bind_int(statement, 22, rule.requiresSignature ? 1 : 0)
    }

    static func bind(connection: Connection, to statement: OpaquePointer?) {
        SQLiteHandle.bindText(statement, index: 1, value: connection.id.uuidString)
        sqlite3_bind_int(statement, 2, connection.pid)
        SQLiteHandle.bindText(statement, index: 3, value: connection.processName)
        SQLiteHandle.bindText(statement, index: 4, value: connection.processPath)
        SQLiteHandle.bindText(statement, index: 5, value: connection.processBundleId)
        sqlite3_bind_int(statement, 6, Int32(connection.localPort))
        SQLiteHandle.bindText(statement, index: 7, value: connection.remoteHost)
        SQLiteHandle.bindText(statement, index: 8, value: connection.remoteIP)
        sqlite3_bind_int(statement, 9, Int32(connection.remotePort))
        SQLiteHandle.bindText(statement, index: 10, value: connection.direction.rawValue)
        SQLiteHandle.bindText(statement, index: 11, value: connection.status.rawValue)
        SQLiteHandle.bindText(statement, index: 12, value: connection.protocolName)
        sqlite3_bind_int64(statement, 13, connection.bytesIn)
        sqlite3_bind_int64(statement, 14, connection.bytesOut)
        SQLiteHandle.bindText(statement, index: 15, value: connection.country)
        SQLiteHandle.bindText(statement, index: 16, value: connection.countryCode)
        if let latitude = connection.latitude {
            sqlite3_bind_double(statement, 17, latitude)
        } else {
            sqlite3_bind_null(statement, 17)
        }
        if let longitude = connection.longitude {
            sqlite3_bind_double(statement, 18, longitude)
        } else {
            sqlite3_bind_null(statement, 18)
        }
        sqlite3_bind_double(statement, 19, connection.firstSeen.timeIntervalSince1970)
        sqlite3_bind_double(statement, 20, connection.lastSeen.timeIntervalSince1970)
        SQLiteHandle.bindText(statement, index: 21, value: connection.codeTeamID)
        SQLiteHandle.bindText(statement, index: 22, value: connection.signingStatus.rawValue)
    }
}
