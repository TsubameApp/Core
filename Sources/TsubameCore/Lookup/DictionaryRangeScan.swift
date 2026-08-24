import Foundation

private struct ScanLookupKeyIdentity: Hashable {
    let bytes: Data
    let requiredRules: UInt16?

    init(candidate: PositionedLookupCandidate) {
        bytes = candidate.keyBytes
        requiredRules = candidate.requiredRules?.rawValue
    }
}

private struct RankedScanEntry {
    let candidateIndex: Int
    let storeIndex: Int
    let entry: DictionaryEntry
}

public extension DictionaryLookup {
    /// Finds all dictionary matches which start inside the selected UTF-8 range.
    func scan(_ request: ScanLookupRequest) throws -> [LookupResult] {
        let normalizer = TextNormalizer()
        let normalized = normalizer.normalize(request.text)
        let normalizedScanRange = try normalized.normalizedUTF8Range(
            forOriginalUTF8Range: request.range
        )
        let rules = try JapaneseDeinflectionRules.load()
        let builder = LookupCandidateBuilder(rules: rules)
        let prefixGenerator = PrefixCandidateGenerator()
        let anchorFilter = ScanAnchorFilter()

        var candidates: [PositionedLookupCandidate] = []
        var seenLookupIdentities: Set<ScanLookupKeyIdentity> = []
        var orderedLookupKeys: [DictionaryLookupKey] = []

        let utf8 = request.text.utf8
        let startUTF8Index = utf8.index(
            utf8.startIndex,
            offsetBy: request.range.start
        )
        let endUTF8Index = utf8.index(
            utf8.startIndex,
            offsetBy: request.range.end
        )
        guard var sourceIndex = String.Index(startUTF8Index, within: request.text),
              let sourceEndIndex = String.Index(endUTF8Index, within: request.text) else {
            throw LookupRequestError.offsetIsNotCharacterBoundary(request.range.start)
        }

        var originalOffset = request.range.start
        while sourceIndex < sourceEndIndex {
            let anchorOffset = originalOffset
            let character = request.text[sourceIndex]
            let nextIndex = request.text.index(after: sourceIndex)
            let characterUTF8Length = request.text[sourceIndex..<nextIndex].utf8.count
            sourceIndex = nextIndex
            originalOffset += characterUTF8Length
            guard anchorFilter.shouldScan(
                character,
                normalized: normalizer.normalizedString(String(character))
            ) else { continue }

            let normalizedOffset = try normalized.normalizedUTF8Offset(
                forOriginalUTF8Offset: anchorOffset
            )
            let prefixes = prefixGenerator.candidates(
                in: normalized.text,
                fromUTF8Offset: normalizedOffset,
                throughUTF8Offset: normalizedScanRange.end
            )
            guard !prefixes.isEmpty else { continue }

            let batch = try builder.build(
                prefixes: prefixes,
                normalizedText: normalized,
                originalText: request.text
            )
            if batch.wasTruncated {
                throw DictionaryLookupError.scanCandidateGenerationTruncated(
                    sourceOffset: anchorOffset
                )
            }
            let nextCandidateCount = candidates.count + batch.candidates.count
            guard nextCandidateCount <= LookupCandidateLimits.maximumScanCandidateCount else {
                throw DictionaryLookupError.scanCandidateLimitExceeded(
                    actual: nextCandidateCount,
                    maximum: LookupCandidateLimits.maximumScanCandidateCount
                )
            }
            candidates.append(contentsOf: batch.candidates)

            for candidate in batch.candidates {
                let identity = ScanLookupKeyIdentity(candidate: candidate)
                guard seenLookupIdentities.insert(identity).inserted else { continue }
                let nextKeyCount = orderedLookupKeys.count + 1
                guard nextKeyCount
                        <= LookupCandidateLimits.maximumScanUniqueLookupKeyCount else {
                    throw DictionaryLookupError.scanUniqueKeyLimitExceeded(
                        actual: nextKeyCount,
                        maximum: LookupCandidateLimits.maximumScanUniqueLookupKeyCount
                    )
                }
                orderedLookupKeys.append(
                    DictionaryLookupKey(
                        key: candidate.key,
                        requiredRules: candidate.requiredRules
                    )
                )
            }
        }

        guard !orderedLookupKeys.isEmpty else { return [] }

        var loadedEntries: [(storeIndex: Int, entry: DictionaryEntry)] = []
        var lookupBatchCount = 0
        var nextStoreIndex = 0

        func execute(_ keys: ArraySlice<DictionaryLookupKey>) throws {
            let nextBatchCount = lookupBatchCount + 1
            guard nextBatchCount <= LookupCandidateLimits.maximumScanLookupBatchCount else {
                throw DictionaryLookupError.scanBatchLimitExceeded(
                    actual: nextBatchCount,
                    maximum: LookupCandidateLimits.maximumScanLookupBatchCount
                )
            }
            lookupBatchCount = nextBatchCount
            let entries = try store.lookup(
                keys: Array(keys),
                limit: LookupRequestLimits.maximumEntriesPerGroup
            )

            if entries.count == LookupRequestLimits.maximumEntriesPerGroup,
               keys.count > 1 {
                let middle = keys.index(
                    keys.startIndex,
                    offsetBy: keys.count / 2
                )
                try execute(keys[..<middle])
                try execute(keys[middle...])
                return
            }

            for entry in entries {
                loadedEntries.append((nextStoreIndex, entry))
                nextStoreIndex += 1
            }
        }

        var batchStart = orderedLookupKeys.startIndex
        while batchStart < orderedLookupKeys.endIndex {
            let batchEnd = min(
                batchStart + LookupCandidateLimits.maximumLookupKeyCount,
                orderedLookupKeys.endIndex
            )
            try execute(orderedLookupKeys[batchStart..<batchEnd])
            batchStart = batchEnd
        }

        var candidateIndicesByBytes: [Data: [Int]] = [:]
        for (index, candidate) in candidates.enumerated() {
            candidateIndicesByBytes[candidate.keyBytes, default: []].append(index)
        }

        var entriesByRange: [UTF8TextRange: [Int64: RankedScanEntry]] = [:]
        for loaded in loadedEntries {
            let entryRules = DictionaryRuleSet.parse(loaded.entry.rules)
            for match in loaded.entry.matches {
                let bytes = Data(match.key.utf8)
                guard let candidateIndices = candidateIndicesByBytes[bytes] else { continue }
                for candidateIndex in candidateIndices {
                    let candidate = candidates[candidateIndex]
                    if let requiredRules = candidate.requiredRules,
                       requiredRules.intersection(entryRules).isEmpty {
                        continue
                    }
                    let ranked = RankedScanEntry(
                        candidateIndex: candidateIndex,
                        storeIndex: loaded.storeIndex,
                        entry: loaded.entry
                    )
                    let existing = entriesByRange[candidate.sourceRange]?[loaded.entry.id]
                    let shouldReplace = if let existing {
                        candidateIndex < existing.candidateIndex
                            || (candidateIndex == existing.candidateIndex
                                && loaded.storeIndex < existing.storeIndex)
                    } else {
                        true
                    }
                    if shouldReplace {
                        entriesByRange[candidate.sourceRange, default: [:]][loaded.entry.id] = ranked
                    }
                }
            }
        }

        return entriesByRange
            .map { range, rankedEntries in
                let entries = rankedEntries.values
                    .sorted {
                        if $0.candidateIndex != $1.candidateIndex {
                            return $0.candidateIndex < $1.candidateIndex
                        }
                        return $0.storeIndex < $1.storeIndex
                    }
                    .prefix(request.entriesPerGroupLimit)
                    .map(\.entry)
                return LookupResult(sourceRange: range, entries: entries)
            }
            .sorted {
                if $0.sourceRange.start != $1.sourceRange.start {
                    return $0.sourceRange.start < $1.sourceRange.start
                }
                if $0.sourceRange.end != $1.sourceRange.end {
                    return $0.sourceRange.end > $1.sourceRange.end
                }
                return false
            }
            .prefix(request.resultGroupLimit)
            .map { $0 }
    }
}
