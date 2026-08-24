import Foundation

public enum DictionaryImportPhase: String, Sendable, Equatable {
    case sourcePreparation = "source preparation"
    case resourceCopy = "resource inventory and copy"
    case databaseTransaction = "database transaction"
    case databaseSchema = "database schema"
    case databaseIndices = "database indices"
    case databaseIntegrity = "database integrity"
    case manifest = "manifest"
    case bundleValidation = "bundle validation"
    case publication = "atomic publication"
}

public enum DictionaryBankKind: String, Sendable, Equatable {
    case term
    case termMetadata = "term metadata"
    case kanji
    case kanjiMetadata = "kanji metadata"
    case tag
}

public enum DictionaryImportProgressEvent: Sendable, Equatable {
    case phaseStarted(DictionaryImportPhase)
    case phaseFinished(DictionaryImportPhase, elapsedSeconds: Double)
    case bankStarted(
        kind: DictionaryBankKind,
        fileName: String,
        index: Int,
        total: Int
    )
    case bankFinished(
        kind: DictionaryBankKind,
        fileName: String,
        index: Int,
        total: Int,
        entryCount: Int,
        elapsedSeconds: Double
    )
    case completed(elapsedSeconds: Double)
}

public typealias DictionaryImportProgressHandler = @Sendable (
    DictionaryImportProgressEvent
) -> Void

struct DictionaryImportTimer {
    private let startedAt = ContinuousClock.now

    var elapsedSeconds: Double {
        let components = startedAt.duration(to: .now).components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
