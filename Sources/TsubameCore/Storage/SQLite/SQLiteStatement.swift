import Foundation

#if os(Windows)
import CSQLiteBundled
#else
import CSQLiteSystem
#endif

enum SQLiteStepResult: Sendable, Equatable {
    case row
    case done
}

enum SQLiteColumnType: Sendable, Equatable {
    case integer
    case real
    case text
    case blob
    case null
}

final class SQLiteStatement {
    private let connection: SQLiteConnection
    private var statement: OpaquePointer?
    private let sql: String
    private var hasCurrentRow = false

    init(connection: SQLiteConnection, statement: OpaquePointer, sql: String) {
        self.connection = connection
        self.statement = statement
        self.sql = sql
    }

    deinit {
        finalizeIgnoringErrors()
    }

    func bindNull(at index: Int32) throws {
        try check(sqlite3_bind_null(try requireStatement(), index), operation: "bind null")
    }

    func bind(_ value: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(try requireStatement(), index, value), operation: "bind integer")
    }

    func bind(_ value: Double, at index: Int32) throws {
        try check(sqlite3_bind_double(try requireStatement(), index, value), operation: "bind real")
    }

    func bind(_ value: String, at index: Int32) throws {
        let statement = try requireStatement()
        let resultCode = value.withCString { characters in
            sqlite3_bind_text(statement, index, characters, -1, sqliteTransient)
        }
        try check(resultCode, operation: "bind text")
    }

    func bind(_ value: Data, at index: Int32) throws {
        let statement = try requireStatement()

        guard value.count <= Int(Int32.max) else {
            throw SQLiteError(
                resultCode: SQLITE_TOOBIG,
                extendedResultCode: SQLITE_TOOBIG,
                operation: "bind blob",
                message: "The blob exceeds SQLite's binding size limit.",
                sql: sql
            )
        }

        if value.isEmpty {
            try check(sqlite3_bind_zeroblob(statement, index, 0), operation: "bind empty blob")
            return
        }

        let resultCode = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                index,
                bytes.baseAddress,
                Int32(bytes.count),
                sqliteTransient
            )
        }
        try check(resultCode, operation: "bind blob")
    }

    func step() throws -> SQLiteStepResult {
        let resultCode = sqlite3_step(try requireStatement())

        switch resultCode {
        case SQLITE_ROW:
            hasCurrentRow = true
            return .row
        case SQLITE_DONE:
            hasCurrentRow = false
            return .done
        default:
            hasCurrentRow = false
            throw connection.makeError(resultCode: resultCode, operation: "step", sql: sql)
        }
    }

    func reset(clearingBindings: Bool = true) throws {
        let statement = try requireStatement()
        let resetResult = sqlite3_reset(statement)
        hasCurrentRow = false
        try check(resetResult, operation: "reset")

        if clearingBindings {
            try check(sqlite3_clear_bindings(statement), operation: "clear bindings")
        }
    }

    func finalize() throws {
        guard let statement else {
            return
        }

        self.statement = nil
        hasCurrentRow = false
        let resultCode = sqlite3_finalize(statement)
        try check(resultCode, operation: "finalize")
    }

    func columnType(at index: Int32) -> SQLiteColumnType {
        let statement = requireCurrentRow()

        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer
        case SQLITE_FLOAT:
            return .real
        case SQLITE_TEXT:
            return .text
        case SQLITE_BLOB:
            return .blob
        default:
            return .null
        }
    }

    func integer(at index: Int32) -> Int64 {
        sqlite3_column_int64(requireCurrentRow(), index)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(requireCurrentRow(), index)
    }

    func string(at index: Int32) -> String? {
        let statement = requireCurrentRow()
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let characters = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: characters)
    }

    func data(at index: Int32) -> Data? {
        let statement = requireCurrentRow()
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        let byteCount = Int(sqlite3_column_bytes(statement, index))
        guard byteCount > 0 else {
            return Data()
        }
        guard let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(bytes: bytes, count: byteCount)
    }

    func finalizeIgnoringErrors() {
        guard let statement else {
            return
        }
        self.statement = nil
        hasCurrentRow = false
        sqlite3_finalize(statement)
    }

    private func requireStatement() throws -> OpaquePointer {
        guard let statement else {
            throw SQLiteError(
                resultCode: SQLITE_MISUSE,
                extendedResultCode: SQLITE_MISUSE,
                operation: "statement access",
                message: "The statement is finalized.",
                sql: sql
            )
        }
        return statement
    }

    private func requireCurrentRow() -> OpaquePointer {
        precondition(hasCurrentRow, "Column values require a current SQLite row.")
        guard let statement else {
            preconditionFailure("Column values require a non-finalized SQLite statement.")
        }
        return statement
    }

    private func check(_ resultCode: Int32, operation: String) throws {
        guard resultCode == SQLITE_OK else {
            throw connection.makeError(resultCode: resultCode, operation: operation, sql: sql)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
