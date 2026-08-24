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

        let rules = try JapaneseDeinflectionRules.load()
        let candidateBatch = try LookupCandidateBuilder(rules: rules).build(
            prefixes: candidates,
            normalizedText: normalized
        )
        let entries = try store.lookup(
            keys: candidateBatch.lookupKeys,
            limit: request.resultLimit
        )
        guard !entries.isEmpty else {
            return emptyResult(at: request.position)
        }

        var ranked: [(candidateIndex: Int, storeIndex: Int, entry: DictionaryEntry)] = []
        ranked.reserveCapacity(entries.count)
        var seenEntryIDs: Set<Int64> = []
        for (storeIndex, entry) in entries.enumerated()
            where seenEntryIDs.insert(entry.id).inserted {
            let matchBytes = entry.matches.map { Data($0.key.utf8) }
            let entryRules = DictionaryRuleSet.parse(entry.rules)
            guard let candidateIndex = candidateBatch.candidates.firstIndex(where: { candidate in
                guard matchBytes.contains(candidate.keyBytes) else { return false }
                guard let requiredRules = candidate.requiredRules else { return true }
                return !requiredRules.intersection(entryRules).isEmpty
            }) else {
                continue
            }
            ranked.append((candidateIndex, storeIndex, entry))
        }
        guard let best = ranked.min(by: {
            if $0.candidateIndex != $1.candidateIndex {
                return $0.candidateIndex < $1.candidateIndex
            }
            return $0.storeIndex < $1.storeIndex
        }) else {
            return emptyResult(at: request.position)
        }
        let bestRange = candidateBatch.candidates[best.candidateIndex].sourceRange
        let resultEntries = ranked
            .filter { candidateBatch.candidates[$0.candidateIndex].sourceRange == bestRange }
            .sorted {
                if $0.candidateIndex != $1.candidateIndex {
                    return $0.candidateIndex < $1.candidateIndex
                }
                return $0.storeIndex < $1.storeIndex
            }
            .prefix(request.resultLimit)
            .map(\.entry)
        return LookupResult(sourceRange: bestRange, entries: resultEntries)
    }

    private func emptyResult(at position: Int) -> LookupResult {
        LookupResult(
            sourceRange: UTF8TextRange(start: position, end: position),
            entries: []
        )
    }
}
