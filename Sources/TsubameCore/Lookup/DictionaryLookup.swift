import Foundation

/// Performs dictionary lookup from a position in arbitrary source text.
public struct DictionaryLookup {
    private let store: any DictionaryStore
    private let normalizer: TextNormalizer
    private let candidateGenerator: PrefixCandidateGenerator

    /// Creates a positioned lookup service backed by one dictionary store.
    public init(store: any DictionaryStore) {
        self.store = store
        normalizer = TextNormalizer()
        candidateGenerator = PrefixCandidateGenerator()
    }

    /// Returns entries for the longest dictionary prefix at the request position.
    public func lookup(_ request: PositionedLookupRequest) throws -> LookupResult {
        let normalized = normalizer.normalize(request.text)
        let normalizedPosition = try normalized.normalizedUTF8Offset(
            forOriginalUTF8Offset: request.position
        )
        let candidates = candidateGenerator.candidates(
            in: normalized.text,
            fromUTF8Offset: normalizedPosition
        )
        guard !candidates.isEmpty else {
            return emptyResult(at: request.position)
        }

        let entries = try store.lookup(
            keys: candidates.map(\.key),
            limit: request.resultLimit
        )
        guard !entries.isEmpty else {
            return emptyResult(at: request.position)
        }

        for candidate in candidates {
            let matchingEntries = entries.filter { entry in
                entry.matches.contains { match in
                    match.key.utf8.elementsEqual(candidate.key.utf8)
                }
            }
            guard !matchingEntries.isEmpty else { continue }

            let sourceRange = try normalized.originalUTF8Range(
                forNormalizedUTF8Range: candidate.normalizedRange
            )
            return LookupResult(
                sourceRange: sourceRange,
                entries: matchingEntries
            )
        }
        return emptyResult(at: request.position)
    }

    private func emptyResult(at position: Int) -> LookupResult {
        LookupResult(
            sourceRange: UTF8TextRange(start: position, end: position),
            entries: []
        )
    }
}
