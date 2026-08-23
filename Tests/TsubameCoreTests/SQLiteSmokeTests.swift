import Foundation
import XCTest
@testable import TsubameCore

final class SQLiteSmokeTests: XCTestCase {
    func testCreatesWritesClosesAndReopensDatabase() throws {
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
                XCTAssertEqual(try insert.step(), .done)
                try insert.finalize()
                try connection.close()
            }

            do {
                let connection = try SQLiteConnection(url: databaseURL, mode: .readOnly)
                let select = try connection.prepare(
                    "SELECT id, name, score, payload, note FROM sample WHERE id = ?"
                )
                try select.bind(Int64(1), at: 1)

                XCTAssertEqual(try select.step(), .row)
                XCTAssertEqual(select.columnType(at: 0), .integer)
                XCTAssertEqual(select.integer(at: 0), 1)
                XCTAssertEqual(select.string(at: 1), "食べる")
                XCTAssertEqual(select.double(at: 2), 1.5, accuracy: 0.000_001)
                XCTAssertEqual(select.data(at: 3), payload)
                XCTAssertEqual(select.columnType(at: 4), .null)
                XCTAssertNil(select.string(at: 4))
                XCTAssertEqual(try select.step(), .done)

                try select.finalize()
                try connection.close()
            }
        }
    }

    func testTransactionRollsBackWhenBodyThrows() throws {
        enum ExpectedFailure: Error {
            case rollback
        }

        try withTemporaryDatabase { databaseURL in
            let connection = try SQLiteConnection(url: databaseURL)
            defer { try? connection.close() }

            try connection.execute("CREATE TABLE sample (value TEXT NOT NULL)")

            XCTAssertThrowsError(
                try connection.inTransaction {
                    let insert = try connection.prepare("INSERT INTO sample (value) VALUES (?)")
                    try insert.bind("must roll back", at: 1)
                    XCTAssertEqual(try insert.step(), .done)
                    try insert.finalize()
                    throw ExpectedFailure.rollback
                }
            ) { error in
                guard case ExpectedFailure.rollback = error else {
                    return XCTFail("Expected rollback marker, got \(error)")
                }
            }

            let count = try connection.prepare("SELECT COUNT(*) FROM sample")
            XCTAssertEqual(try count.step(), .row)
            XCTAssertEqual(count.integer(at: 0), 0)
            try count.finalize()
        }
    }

    func testMapsSQLiteErrorsAndReportsRuntimeDiagnostics() throws {
        try withTemporaryDatabase { databaseURL in
            let connection = try SQLiteConnection(url: databaseURL)
            defer { try? connection.close() }

            XCTAssertFalse(SQLiteConnection.libraryVersion.isEmpty)
            XCTAssertFalse(SQLiteConnection.compileOptions.isEmpty)
            print(
                "SQLite \(SQLiteConnection.libraryVersion); "
                    + "\(SQLiteConnection.compileOptions.count) compile options"
            )

            XCTAssertThrowsError(try connection.execute("NOT VALID SQL")) { error in
                guard let sqliteError = error as? SQLiteError else {
                    return XCTFail("Expected SQLiteError, got \(error)")
                }

                XCTAssertEqual(sqliteError.resultCode, 1)
                XCTAssertEqual(sqliteError.operation, "prepare")
                XCTAssertEqual(sqliteError.sql, "NOT VALID SQL")
                XCTAssertFalse(sqliteError.message.isEmpty)
            }
        }
    }

    func testStatementCanBeResetAndReused() throws {
        try withTemporaryDatabase { databaseURL in
            let connection = try SQLiteConnection(url: databaseURL)
            defer { try? connection.close() }

            let statement = try connection.prepare("SELECT ?")

            try statement.bind("first", at: 1)
            XCTAssertEqual(try statement.step(), .row)
            XCTAssertEqual(statement.string(at: 0), "first")
            XCTAssertEqual(try statement.step(), .done)

            try statement.reset()
            try statement.bind("second", at: 1)
            XCTAssertEqual(try statement.step(), .row)
            XCTAssertEqual(statement.string(at: 0), "second")
            XCTAssertEqual(try statement.step(), .done)
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
