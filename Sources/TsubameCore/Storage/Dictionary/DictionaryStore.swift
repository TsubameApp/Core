import Foundation

public struct DictionaryLookupKey: Sendable, Equatable {
    public let key: String
    /// `nil` means that the key is not constrained by dictionary rules.
    public let requiredRules: DictionaryRuleSet?

    public init(key: String, requiredRules: DictionaryRuleSet? = nil) {
        self.key = key
        self.requiredRules = requiredRules
    }
}

public protocol DictionaryStore {
    func lookup(keys: [DictionaryLookupKey], limit: Int) throws -> [DictionaryEntry]
}

public extension DictionaryStore {
    /// Performs an unconstrained exact lookup using raw and NFKC key variants.
    func lookup(keys: [String], limit: Int) throws -> [DictionaryEntry] {
        var seenUTF8: Set<Data> = []
        var prepared: [DictionaryLookupKey] = []
        prepared.reserveCapacity(keys.count * 2)
        let normalizer = TextNormalizer()

        for key in keys where !key.isEmpty {
            let normalizedKey = normalizer.normalizedString(key)
            for candidate in [key, normalizedKey] where !candidate.isEmpty {
                guard seenUTF8.insert(Data(candidate.utf8)).inserted else { continue }
                prepared.append(DictionaryLookupKey(key: candidate))
            }
        }
        return try lookup(keys: prepared, limit: limit)
    }
}

public enum DictionaryStoreError: LocalizedError, Sendable, Equatable {
    case databaseIsNotLocalFile(URL)
    case invalidLimit(Int)
    case resultLimitTooLarge(actual: Int, maximum: Int)
    case tooManyLookupKeys(actual: Int, maximum: Int)
    case emptyRequiredRules
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
        case .emptyRequiredRules:
            return "A constrained dictionary lookup key must require at least one rule."
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
