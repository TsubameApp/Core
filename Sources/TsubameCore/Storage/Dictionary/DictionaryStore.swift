import Foundation

public protocol DictionaryStore {
    func lookup(keys: [String], limit: Int) throws -> [DictionaryEntry]
}

public enum DictionaryStoreError: LocalizedError, Sendable, Equatable {
    case databaseIsNotLocalFile(URL)
    case invalidLimit(Int)
    case resultLimitTooLarge(actual: Int, maximum: Int)
    case tooManyLookupKeys(actual: Int, maximum: Int)
    case unsupportedSchemaVersion(actual: Int64, expected: Int)
    case invalidStoredLookupKeyType(String)
    case invalidStoredEntry
    case invalidStoredDefinition

    public var errorDescription: String? {
        switch self {
        case .databaseIsNotLocalFile(let url):
            return "Dictionary database is not a local file URL: \(url.absoluteString)"
        case .invalidLimit(let limit):
            return "Dictionary lookup limit must be greater than zero: \(limit)"
        case .resultLimitTooLarge(let actual, let maximum):
            return "Dictionary lookup limit is \(actual); the maximum is \(maximum)."
        case .tooManyLookupKeys(let actual, let maximum):
            return "Dictionary lookup received \(actual) keys; the limit is \(maximum)."
        case .unsupportedSchemaVersion(let actual, let expected):
            return "Dictionary schema version \(actual) is unsupported; expected \(expected)."
        case .invalidStoredLookupKeyType(let value):
            return "Dictionary contains an invalid lookup-key type: \(value)"
        case .invalidStoredEntry:
            return "Dictionary contains an invalid term entry."
        case .invalidStoredDefinition:
            return "Dictionary contains an invalid term definition."
        }
    }
}
