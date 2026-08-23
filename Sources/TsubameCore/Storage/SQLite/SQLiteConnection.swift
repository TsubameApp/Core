import Foundation

#if os(Windows)
import CSQLiteBundled
#else
import CSQLiteSystem
#endif

final class SQLiteConnection {
    enum AccessMode {
        case readOnly
        case readWrite
        case readWriteCreate

        var flags: Int32 {
            let mutex = SQLITE_OPEN_FULLMUTEX
            switch self {
            case .readOnly:
                return SQLITE_OPEN_READONLY | mutex
            case .readWrite:
                return SQLITE_OPEN_READWRITE | mutex
            case .readWriteCreate:
                return SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | mutex
            }
        }
    }

    private var database: OpaquePointer?

    init(url: URL, mode: AccessMode = .readWriteCreate) throws {
        precondition(url.isFileURL, "SQLite databases require a file URL.")

        var database: OpaquePointer?
        let resultCode = sqlite3_open_v2(url.path, &database, mode.flags, nil)

        guard resultCode == SQLITE_OK, let database else {
            let error = Self.makeError(
                database: database,
                resultCode: resultCode,
                operation: "open",
                sql: nil
            )
            if let database {
                sqlite3_close_v2(database)
            }
            throw error
        }

        self.database = database
        sqlite3_extended_result_codes(database, 1)
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    static var libraryVersion: String {
        String(cString: sqlite3_libversion())
    }

    static var compileOptions: [String] {
        var options: [String] = []
        var index: Int32 = 0

        while let option = sqlite3_compileoption_get(index) {
            options.append(String(cString: option))
            index += 1
        }

        return options
    }

    func close() throws {
        guard let database else {
            return
        }

        let resultCode = sqlite3_close(database)
        guard resultCode == SQLITE_OK else {
            throw makeError(resultCode: resultCode, operation: "close")
        }

        self.database = nil
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        let database = try requireDatabase()
        var statement: OpaquePointer?
        let resultCode = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard resultCode == SQLITE_OK, let statement else {
            throw makeError(resultCode: resultCode, operation: "prepare", sql: sql)
        }

        return SQLiteStatement(connection: self, statement: statement, sql: sql)
    }

    func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        defer { statement.finalizeIgnoringErrors() }

        while try statement.step() == .row {}
    }

    func inTransaction<Result>(_ body: () throws -> Result) throws -> Result {
        try execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func interrupt() {
        if let database {
            sqlite3_interrupt(database)
        }
    }

    func makeError(
        resultCode: Int32,
        operation: String,
        sql: String? = nil
    ) -> SQLiteError {
        Self.makeError(
            database: database,
            resultCode: resultCode,
            operation: operation,
            sql: sql
        )
    }

    private func requireDatabase() throws -> OpaquePointer {
        guard let database else {
            throw SQLiteError(
                resultCode: SQLITE_MISUSE,
                extendedResultCode: SQLITE_MISUSE,
                operation: "access",
                message: "The database connection is closed.",
                sql: nil
            )
        }
        return database
    }

    private static func makeError(
        database: OpaquePointer?,
        resultCode: Int32,
        operation: String,
        sql: String?
    ) -> SQLiteError {
        let extendedResultCode = database.map(sqlite3_extended_errcode) ?? resultCode
        let message: String

        if let database {
            message = String(cString: sqlite3_errmsg(database))
        } else if let errorString = sqlite3_errstr(resultCode) {
            message = String(cString: errorString)
        } else {
            message = "Unknown SQLite error."
        }

        return SQLiteError(
            resultCode: resultCode & 0xff,
            extendedResultCode: extendedResultCode,
            operation: operation,
            message: message,
            sql: sql
        )
    }
}
