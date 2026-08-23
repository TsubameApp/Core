import Foundation

struct SQLiteError: Error, Sendable, Equatable, LocalizedError {
    let resultCode: Int32
    let extendedResultCode: Int32
    let operation: String
    let message: String
    let sql: String?

    var errorDescription: String? {
        var description = "SQLite \(operation) failed (\(extendedResultCode)): \(message)"
        if let sql {
            description += " [SQL: \(sql)]"
        }
        return description
    }
}
