import Foundation
import Testing
@testable import TsubameCore

@Suite
struct SQLiteSmokeTests {
    @Test func createsWritesClosesAndReopensDatabase() throws {
        try withTemporaryDatabase { databaseURL in
            let payload = Data([0x00, 0x01, 0xfe, 0xff])

            do {
                let connection = try SQLiteConnection(url: databaseURL)
                try connection.execute(
                    """
                    CREATE TABLE sample (
                        id INTEGER PRIMARY KEY,
                        name TEXT NOT NULL,
                        score REAL NOT NULL,
                        payload BLOB NOT NULL,
                        note TEXT
                    )
                    """
                )

                let insert = try connection.prepare(
                    "INSERT INTO sample (id, name, score, payload, note) VALUES (?, ?, ?, ?, ?)"
                )
                try insert.bind(Int64(1), at: 1)
                try insert.bind("食べる", at: 2)
                try insert.bind(1.5, at: 3)
                try insert.bind(payload, at: 4)
                try insert.bindNull(at: 5)
                #expect(try insert.step() == .done)
                try insert.finalize()
                try connection.close()
            }

            do {
                let connection = try SQLiteConnection(url: databaseURL, mode: .readOnly)
                let select = try connection.prepare(
                    "SELECT id, name, score, payload, note FROM sample WHERE id = ?"
                )
                try select.bind(Int64(1), at: 1)

                #expect(try select.step() == .row)
                #expect(select.columnType(at: 0) == .integer)
                #expect(select.integer(at: 0) == 1)
                #expect(select.string(at: 1) == "食べる")
                #expect(abs(select.double(at: 2) - 1.5) <= 0.000_001)
                #expect(select.data(at: 3) == payload)
                #expect(select.columnType(at: 4) == .null)
                #expect(select.string(at: 4) == nil)
                #expect(try select.step() == .done)

                try select.finalize()
                try connection.close()
            }
        }
    }

    @Test func transactionRollsBackWhenBodyThrows() throws {
        enum ExpectedFailure: Error {
            case rollback
        }

        try withTemporaryDatabase { databaseURL in
            let connection = try SQLiteConnection(url: databaseURL)
            defer { try? connection.close() }

            try connection.execute("CREATE TABLE sample (value TEXT NOT NULL)")

            #expect(throws: ExpectedFailure.rollback) {
                try connection.inTransaction {
                    let insert = try connection.prepare("INSERT INTO sample (value) VALUES (?)")
                    try insert.bind("must roll back", at: 1)
                    #expect(try insert.step() == .done)
                    try insert.finalize()
                    throw ExpectedFailure.rollback
                }
            }

            let count = try connection.prepare("SELECT COUNT(*) FROM sample")
            #expect(try count.step() == .row)
            #expect(count.integer(at: 0) == 0)
            try count.finalize()
        }
    }

    @Test func mapsSQLiteErrorsAndReportsRuntimeDiagnostics() throws {
        try withTemporaryDatabase { databaseURL in
            let connection = try SQLiteConnection(url: databaseURL)
            defer { try? connection.close() }

            #expect(!SQLiteConnection.libraryVersion.isEmpty)
            #expect(!SQLiteConnection.compileOptions.isEmpty)
            print(
                "SQLite \(SQLiteConnection.libraryVersion); "
                    + "\(SQLiteConnection.compileOptions.count) compile options"
            )

            do {
                try connection.execute("NOT VALID SQL")
                Issue.record("Expected invalid SQL to throw SQLiteError")
            } catch let sqliteError as SQLiteError {
                #expect(sqliteError.resultCode == 1)
                #expect(sqliteError.operation == "prepare")
                #expect(sqliteError.sql == "NOT VALID SQL")
                #expect(!sqliteError.message.isEmpty)
            } catch {
                Issue.record("Expected SQLiteError, got \(error)")
            }
        }
    }

    @Test func statementCanBeResetAndReused() throws {
        try withTemporaryDatabase { databaseURL in
            let connection = try SQLiteConnection(url: databaseURL)
            defer { try? connection.close() }

            let statement = try connection.prepare("SELECT ?")

            try statement.bind("first", at: 1)
            #expect(try statement.step() == .row)
            #expect(statement.string(at: 0) == "first")
            #expect(try statement.step() == .done)

            try statement.reset()
            try statement.bind("second", at: 1)
            #expect(try statement.step() == .row)
            #expect(statement.string(at: 0) == "second")
            #expect(try statement.step() == .done)
            try statement.finalize()
        }
    }

    private func withTemporaryDatabase(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "TsubameSQLiteTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(directory.appending(path: "test.sqlite"))
    }
}
