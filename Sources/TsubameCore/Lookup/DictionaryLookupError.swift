import Foundation

public enum DictionaryLookupError: LocalizedError, Sendable, Equatable {
    case scanCandidateGenerationTruncated(sourceOffset: Int)
    case scanCandidateLimitExceeded(actual: Int, maximum: Int)
    case scanUniqueKeyLimitExceeded(actual: Int, maximum: Int)
    case scanBatchLimitExceeded(actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .scanCandidateGenerationTruncated(let sourceOffset):
            "Range scan candidate generation was truncated at UTF-8 offset \(sourceOffset)."
        case let .scanCandidateLimitExceeded(actual, maximum):
            "Range scan generated \(actual) candidates; maximum is \(maximum)."
        case let .scanUniqueKeyLimitExceeded(actual, maximum):
            "Range scan generated \(actual) unique lookup keys; maximum is \(maximum)."
        case let .scanBatchLimitExceeded(actual, maximum):
            "Range scan requires \(actual) dictionary batches; maximum is \(maximum)."
        }
    }
}
