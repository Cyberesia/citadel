import Foundation
import SQLite3

/// Citadel firewall persistence — rules, connections, profiles, blocklists, and sightings.
public final class RuleStore: @unchecked Sendable {
    private let database: SQLiteHandle
    public var path: String { database.path }

    public init(path: String) throws {
        database = try SQLiteHandle(path: path)
        try migrate()
        try seedDefaults()
    }

    // MARK: - Schema

    private func migrate() throws {
        try database.exec(RuleStoreSchema.migrationsBootstrap)
        let appliedVersion = currentSchemaVersion()
        if appliedVersion < 1 {
            try database.exec(RuleStoreSchema.version1)
            try recordMigration(1)
        }
        if appliedVersion < 2 {
            try database.exec(RuleStoreSchema.version2)
            try recordMigration(2)
        }
    }

    private func currentSchemaVersion() -> Int {
        database.sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(
                database.db,
                "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return 0 }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func recordMigration(_ version: Int) throws {
        try database.run("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (?, ?);") { statement in
            sqlite3_bind_int(statement, 1, Int32(version))
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        }
    }

    private func seedDefaults() throws {
        for profile in RuleStoreSchema.defaultProfiles {
            try insertProfileIfMissing(profile)
        }
        for blocklist in RuleStoreSchema.defaultBlocklists {
            try insertBlocklistIfMissing(blocklist)
        }
    }

    // MARK: - Rules

    public func upsertRule(_ rule: Rule) throws {
        try database.run("""
        INSERT OR REPLACE INTO rules(
            id, process_bundle_id, process_path, process_name, remote_host, remote_ip,
            remote_port, direction, action, scope, priority, profile, group_name, notes,
            enabled, temporary, created_at, expires_at, last_used_at, hit_count,
            code_team_id, requires_signature
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """) { statement in
            RuleStoreRowMapping.bind(rule: rule, to: statement)
        }
    }

    public func deleteRule(id: UUID) throws {
        try database.run("DELETE FROM rules WHERE id=?;") { statement in
            SQLiteHandle.bindText(statement, index: 1, value: id.uuidString)
        }
    }

    public func purgeExpiredRules(now: Date = Date()) throws {
        try database.run("DELETE FROM rules WHERE expires_at IS NOT NULL AND expires_at < ?;") { statement in
            sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
        }
    }

    public func purgeSessionRules() throws {
        try database.exec("DELETE FROM rules WHERE temporary=1 AND notes LIKE '%Until quit%';")
        try database.exec("DELETE FROM rules WHERE temporary=1 AND notes LIKE '%session%';")
    }

    public func allRules(profile: String? = nil) -> [Rule] {
        database.sync {
            let sql: String
            if profile != nil {
                sql = """
                SELECT id, process_bundle_id, process_path, process_name, remote_host, remote_ip,
                       remote_port, direction, action, scope, priority, profile, group_name, notes,
                       enabled, temporary, created_at, expires_at, last_used_at, hit_count,
                       code_team_id, requires_signature
                FROM rules WHERE profile=? ORDER BY priority DESC, created_at DESC;
                """
            } else {
                sql = """
                SELECT id, process_bundle_id, process_path, process_name, remote_host, remote_ip,
                       remote_port, direction, action, scope, priority, profile, group_name, notes,
                       enabled, temporary, created_at, expires_at, last_used_at, hit_count,
                       code_team_id, requires_signature
                FROM rules ORDER BY priority DESC, created_at DESC;
                """
            }

            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            if let profile {
                SQLiteHandle.bindText(statement, index: 1, value: profile)
            }

            var rules: [Rule] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let rule = RuleStoreRowMapping.rule(from: statement) {
                    rules.append(rule)
                }
            }
            return rules
        }
    }

    // MARK: - Profiles / blocklists / settings

    public func allProfiles() -> [Profile] {
        database.sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(database.db, "SELECT id,name,mode,icon,is_active FROM profiles ORDER BY name;", -1, &statement, nil) == SQLITE_OK else {
                return []
            }
            var profiles: [Profile] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let profile = RuleStoreRowMapping.profile(from: statement) {
                    profiles.append(profile)
                }
            }
            return profiles
        }
    }

    public func setActiveProfile(name: String) throws {
        try database.exec("UPDATE profiles SET is_active=0;")
        try database.run("UPDATE profiles SET is_active=1 WHERE name=?;") { statement in
            SQLiteHandle.bindText(statement, index: 1, value: name)
        }
    }

    public func allBlocklists() -> [BlocklistInfo] {
        database.sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(database.db, "SELECT id,name,url,enabled,last_updated,entry_count FROM blocklists ORDER BY name;", -1, &statement, nil) == SQLITE_OK else {
                return []
            }
            var blocklists: [BlocklistInfo] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let blocklist = RuleStoreRowMapping.blocklist(from: statement) {
                    blocklists.append(blocklist)
                }
            }
            return blocklists
        }
    }

    public func updateBlocklist(_ blocklist: BlocklistInfo) throws {
        try database.run("UPDATE blocklists SET enabled=?, last_updated=?, entry_count=? WHERE id=?;") { statement in
            sqlite3_bind_int(statement, 1, blocklist.enabled ? 1 : 0)
            if let updated = blocklist.lastUpdated {
                sqlite3_bind_double(statement, 2, updated.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            sqlite3_bind_int(statement, 3, Int32(blocklist.entryCount))
            SQLiteHandle.bindText(statement, index: 4, value: blocklist.id.uuidString)
        }
    }

    public func setSetting(_ key: String, _ value: String) throws {
        try database.run("INSERT OR REPLACE INTO settings(key,value) VALUES(?,?);") { statement in
            SQLiteHandle.bindText(statement, index: 1, value: key)
            SQLiteHandle.bindText(statement, index: 2, value: value)
        }
    }

    public func getSetting(_ key: String) -> String? {
        database.sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(database.db, "SELECT value FROM settings WHERE key=?;", -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            SQLiteHandle.bindText(statement, index: 1, value: key)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return RuleStoreRowMapping.text(statement, column: 0)
        }
    }

    // MARK: - Connections

    public func recordConnection(_ connection: Connection) throws {
        try database.run("""
        INSERT OR REPLACE INTO connections(
            id,pid,process_name,process_path,process_bundle_id,local_port,remote_host,remote_ip,
            remote_port,direction,status,protocol_name,bytes_in,bytes_out,country,country_code,
            latitude,longitude,first_seen,last_seen,code_team_id,signing_status
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """) { statement in
            RuleStoreRowMapping.bind(connection: connection, to: statement)
        }
    }

    public func recentConnections(
        limit: Int = 200,
        status: Connection.Status? = nil,
        since: Date? = nil,
        processName: String? = nil,
        hostQuery: String? = nil
    ) -> [Connection] {
        database.sync {
            var clauses: [String] = []
            if status != nil { clauses.append("status = ?") }
            if since != nil { clauses.append("last_seen >= ?") }
            if processName != nil { clauses.append("process_name LIKE ?") }
            if hostQuery != nil { clauses.append("(remote_host LIKE ? OR remote_ip LIKE ?)") }

            let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let sql = """
            SELECT id,pid,process_name,process_path,process_bundle_id,local_port,remote_host,remote_ip,
                   remote_port,direction,status,protocol_name,bytes_in,bytes_out,country,country_code,
                   latitude,longitude,first_seen,last_seen,code_team_id,signing_status
            FROM connections \(whereClause)
            ORDER BY last_seen DESC LIMIT \(max(1, limit));
            """

            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }

            var bindIndex: Int32 = 1
            if let status {
                SQLiteHandle.bindText(statement, index: bindIndex, value: status.rawValue)
                bindIndex += 1
            }
            if let since {
                sqlite3_bind_double(statement, bindIndex, since.timeIntervalSince1970)
                bindIndex += 1
            }
            if let processName {
                SQLiteHandle.bindText(statement, index: bindIndex, value: "%\(processName)%")
                bindIndex += 1
            }
            if let hostQuery {
                let pattern = "%\(hostQuery)%"
                SQLiteHandle.bindText(statement, index: bindIndex, value: pattern)
                bindIndex += 1
                SQLiteHandle.bindText(statement, index: bindIndex, value: pattern)
            }

            var connections: [Connection] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let connection = RuleStoreRowMapping.connection(from: statement) {
                    connections.append(connection)
                }
            }
            return connections
        }
    }

    public func purgeConnections(olderThan date: Date) throws {
        try database.run("DELETE FROM connections WHERE last_seen < ?;") { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        }
    }

    // MARK: - Sightings

    @discardableResult
    public func recordSighting(kind: String, key: String, at date: Date = Date()) -> Bool {
        database.sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }

            guard sqlite3_prepare_v2(database.db, "SELECT first_seen FROM sightings WHERE kind=? AND key=?;", -1, &statement, nil) == SQLITE_OK else {
                return true
            }
            SQLiteHandle.bindText(statement, index: 1, value: kind)
            SQLiteHandle.bindText(statement, index: 2, value: key)

            if sqlite3_step(statement) == SQLITE_ROW {
                sqlite3_finalize(statement)
                statement = nil
                guard sqlite3_prepare_v2(database.db, "UPDATE sightings SET last_seen=? WHERE kind=? AND key=?;", -1, &statement, nil) == SQLITE_OK else {
                    return false
                }
                sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
                SQLiteHandle.bindText(statement, index: 2, value: kind)
                SQLiteHandle.bindText(statement, index: 3, value: key)
                _ = sqlite3_step(statement)
                return false
            }

            sqlite3_finalize(statement)
            statement = nil
            guard sqlite3_prepare_v2(database.db, "INSERT INTO sightings(kind,key,first_seen,last_seen) VALUES(?,?,?,?);", -1, &statement, nil) == SQLITE_OK else {
                return true
            }
            SQLiteHandle.bindText(statement, index: 1, value: kind)
            SQLiteHandle.bindText(statement, index: 2, value: key)
            sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
            sqlite3_bind_double(statement, 4, date.timeIntervalSince1970)
            _ = sqlite3_step(statement)
            return true
        }
    }

    public func hasSighting(kind: String, key: String) -> Bool {
        database.sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(database.db, "SELECT 1 FROM sightings WHERE kind=? AND key=? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
                return false
            }
            SQLiteHandle.bindText(statement, index: 1, value: kind)
            SQLiteHandle.bindText(statement, index: 2, value: key)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    public func knownTeamIDs() -> Set<String> {
        database.sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(
                database.db,
                "SELECT DISTINCT code_team_id FROM rules WHERE code_team_id IS NOT NULL AND action='allow';",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return [] }

            var teams = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                let team = RuleStoreRowMapping.text(statement, column: 0)
                if !team.isEmpty { teams.insert(team) }
            }
            return teams
        }
    }

    // MARK: - Seed helpers

    private func insertProfileIfMissing(_ profile: Profile) throws {
        try database.run("INSERT OR IGNORE INTO profiles(id,name,mode,icon,is_active) VALUES (?,?,?,?,?);") { statement in
            SQLiteHandle.bindText(statement, index: 1, value: profile.id.uuidString)
            SQLiteHandle.bindText(statement, index: 2, value: profile.name)
            SQLiteHandle.bindText(statement, index: 3, value: profile.mode.rawValue)
            SQLiteHandle.bindText(statement, index: 4, value: profile.icon)
            sqlite3_bind_int(statement, 5, profile.isActive ? 1 : 0)
        }
    }

    private func insertBlocklistIfMissing(_ blocklist: BlocklistInfo) throws {
        try database.run("INSERT OR IGNORE INTO blocklists(id,name,url,enabled,last_updated,entry_count) VALUES (?,?,?,?,?,?);") { statement in
            SQLiteHandle.bindText(statement, index: 1, value: blocklist.id.uuidString)
            SQLiteHandle.bindText(statement, index: 2, value: blocklist.name)
            SQLiteHandle.bindText(statement, index: 3, value: blocklist.url)
            sqlite3_bind_int(statement, 4, blocklist.enabled ? 1 : 0)
            if let updated = blocklist.lastUpdated {
                sqlite3_bind_double(statement, 5, updated.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_int(statement, 6, Int32(blocklist.entryCount))
        }
    }
}
