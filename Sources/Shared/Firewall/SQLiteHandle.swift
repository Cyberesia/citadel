import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-confined SQLite connection wrapper used by `RuleStore`.
final class SQLiteHandle: @unchecked Sendable {
    private var connection: OpaquePointer?
    private let queue = DispatchQueue(label: "com.citadel.firewall.sqlite")

    let path: String

    init(path: String) throws {
        self.path = path
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        if sqlite3_open(path, &connection) != SQLITE_OK {
            throw SQLiteHandleError.openFailed(message: errorMessage())
        }
    }

    deinit {
        if connection != nil {
            sqlite3_close(connection)
        }
    }

    func sync<T>(_ work: () throws -> T) rethrows -> T {
        try queue.sync { try work() }
    }

    var db: OpaquePointer? { connection }

    func exec(_ sql: String) throws {
        try sync {
            var errorMessage: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(connection, sql, nil, nil, &errorMessage) != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "unknown sqlite error"
                sqlite3_free(errorMessage)
                throw SQLiteHandleError.execFailed(message: message)
            }
        }
    }

    func run(_ sql: String, bind: (OpaquePointer?) -> Void) throws {
        try sync {
            var statement: OpaquePointer?
            defer { if statement != nil { sqlite3_finalize(statement) } }
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteHandleError.prepareFailed(message: errorMessage())
            }
            bind(statement)
            let result = sqlite3_step(statement)
            if result != SQLITE_DONE && result != SQLITE_ROW {
                throw SQLiteHandleError.stepFailed(message: errorMessage())
            }
        }
    }

    static func bindText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func errorMessage() -> String {
        guard let connection, let message = sqlite3_errmsg(connection) else { return "unknown" }
        return String(cString: message)
    }
}

enum SQLiteHandleError: LocalizedError {
    case openFailed(message: String)
    case execFailed(message: String)
    case prepareFailed(message: String)
    case stepFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "SQLite open failed: \(message)"
        case .execFailed(let message): return "SQLite exec failed: \(message)"
        case .prepareFailed(let message): return "SQLite prepare failed: \(message)"
        case .stepFailed(let message): return "SQLite step failed: \(message)"
        }
    }
}
