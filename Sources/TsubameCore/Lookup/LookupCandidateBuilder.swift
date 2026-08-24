import Foundation

enum LookupCandidateKind: Int, Sendable, Hashable {
    case exact
    case deinflected
}

struct PositionedLookupCandidate: Sendable, Equatable {
    let key: String
    let keyBytes: Data
    let sourceRange: UTF8TextRange
    let kind: LookupCandidateKind
    let requiredRules: DictionaryRuleSet?
    let path: DeinflectionPath
    let stableOrder: Int

    var depth: Int { path.depth }
}

struct PositionedLookupCandidateBatch: Sendable, Equatable {
    let candidates: [PositionedLookupCandidate]
    let lookupKeys: [DictionaryLookupKey]
    let wasTruncated: Bool
}

struct LookupCandidateBuilder: Sendable {
    private struct LookupIdentity: Hashable {
        let bytes: Data
        let requiredRules: UInt16?
    }

    private struct CandidateIdentity: Hashable {
        let lookup: LookupIdentity
        let sourceRange: UTF8TextRange
        let kind: LookupCandidateKind
    }

    let rules: CompiledDeinflectionRules
    let deinflector: JapaneseDeinflector

    init(rules: CompiledDeinflectionRules) {
        self.rules = rules
        deinflector = JapaneseDeinflector(rules: rules)
    }

    func build(
        prefixes: [LookupPrefixCandidate],
        normalizedText: NormalizedText,
        originalText: String
    ) throws -> PositionedLookupCandidateBatch {
        var candidates: [PositionedLookupCandidate] = []
        var seenCandidates: Set<CandidateIdentity> = []
        var stableOrder = 0
        var traversalWasTruncated = false

        for prefix in prefixes {
            let sourceRange = try normalizedText.originalUTF8Range(
                forNormalizedUTF8Range: prefix.normalizedRange
            )
            appendCandidate(
                key: sourceText(in: originalText, range: sourceRange),
                sourceRange: sourceRange,
                kind: .exact,
                requiredRules: nil,
                path: .empty,
                stableOrder: &stableOrder,
                candidates: &candidates,
                seen: &seenCandidates
            )
            appendCandidate(
                key: prefix.key,
                sourceRange: sourceRange,
                kind: .exact,
                requiredRules: nil,
                path: .empty,
                stableOrder: &stableOrder,
                candidates: &candidates,
                seen: &seenCandidates
            )

            let transformed = deinflector.transform(prefix.key)
            traversalWasTruncated = traversalWasTruncated || transformed.wasTruncated
            for candidate in transformed.candidates where candidate.path.depth > 0 {
                guard let constraint = rules.dictionaryConstraint(
                    for: candidate.conditions
                ) else {
                    continue
                }
                let requiredRules: DictionaryRuleSet?
                switch constraint {
                case .any:
                    requiredRules = nil
                case .required(let rules):
                    requiredRules = rules
                }
                appendCandidate(
                    key: candidate.lemma,
                    sourceRange: sourceRange,
                    kind: .deinflected,
                    requiredRules: requiredRules,
                    path: candidate.path,
                    stableOrder: &stableOrder,
                    candidates: &candidates,
                    seen: &seenCandidates
                )
            }
        }

        candidates.sort(by: isPreferred)

        let exactIdentities = Set(
            candidates.lazy.filter { $0.kind == .exact }.map(lookupIdentity)
        )
        var selectedIdentities = exactIdentities
        var keyBudgetWasTruncated = false
        for candidate in candidates {
            let identity = lookupIdentity(candidate)
            guard !selectedIdentities.contains(identity) else { continue }
            guard selectedIdentities.count < LookupCandidateLimits.maximumLookupKeyCount else {
                keyBudgetWasTruncated = true
                continue
            }
            selectedIdentities.insert(identity)
        }

        var emitted: Set<LookupIdentity> = []
        var lookupKeys: [DictionaryLookupKey] = []
        lookupKeys.reserveCapacity(selectedIdentities.count)
        for candidate in candidates {
            let identity = lookupIdentity(candidate)
            guard selectedIdentities.contains(identity), emitted.insert(identity).inserted else {
                continue
            }
            lookupKeys.append(
                DictionaryLookupKey(
                    key: candidate.key,
                    requiredRules: candidate.requiredRules
                )
            )
        }

        return PositionedLookupCandidateBatch(
            candidates: candidates.filter {
                selectedIdentities.contains(lookupIdentity($0))
            },
            lookupKeys: lookupKeys,
            wasTruncated: traversalWasTruncated || keyBudgetWasTruncated
        )
    }

    private func appendCandidate(
        key: String,
        sourceRange: UTF8TextRange,
        kind: LookupCandidateKind,
        requiredRules: DictionaryRuleSet?,
        path: DeinflectionPath,
        stableOrder: inout Int,
        candidates: inout [PositionedLookupCandidate],
        seen: inout Set<CandidateIdentity>
    ) {
        let bytes = Data(key.utf8)
        let lookup = LookupIdentity(
            bytes: bytes,
            requiredRules: requiredRules?.rawValue
        )
        let identity = CandidateIdentity(
            lookup: lookup,
            sourceRange: sourceRange,
            kind: kind
        )
        guard seen.insert(identity).inserted else { return }
        candidates.append(
            PositionedLookupCandidate(
                key: key,
                keyBytes: bytes,
                sourceRange: sourceRange,
                kind: kind,
                requiredRules: requiredRules,
                path: path,
                stableOrder: stableOrder
            )
        )
        stableOrder += 1
    }

    private func lookupIdentity(_ candidate: PositionedLookupCandidate) -> LookupIdentity {
        LookupIdentity(
            bytes: candidate.keyBytes,
            requiredRules: candidate.requiredRules?.rawValue
        )
    }

    private func sourceText(in text: String, range: UTF8TextRange) -> String {
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: range.start)
        let end = utf8.index(utf8.startIndex, offsetBy: range.end)
        return String(decoding: utf8[start..<end], as: UTF8.self)
    }

    private func isPreferred(
        _ left: PositionedLookupCandidate,
        _ right: PositionedLookupCandidate
    ) -> Bool {
        let leftLength = left.sourceRange.end - left.sourceRange.start
        let rightLength = right.sourceRange.end - right.sourceRange.start
        if leftLength != rightLength { return leftLength > rightLength }
        if left.kind != right.kind { return left.kind == .exact }
        if left.depth != right.depth { return left.depth < right.depth }
        return left.stableOrder < right.stableOrder
    }
}
