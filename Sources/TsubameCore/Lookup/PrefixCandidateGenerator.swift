import Foundation

enum LookupCandidateLimits {
    static let maximumPrefixCharacterCount = 32
    static let maximumPrefixUTF8Length = 256
    static let maximumLookupKeyCount = 500
    static let maximumScanCandidateCount = 16_384
    static let maximumScanUniqueLookupKeyCount = 8_000
    static let maximumScanLookupBatchCount = 16
}

struct LookupPrefixCandidate: Sendable, Equatable {
    let key: String
    let normalizedRange: UTF8TextRange
}

struct PrefixCandidateGenerator: Sendable {
    func candidates(
        in text: String,
        fromUTF8Offset startOffset: Int,
        throughUTF8Offset endOffset: Int? = nil
    ) -> [LookupPrefixCandidate] {
        let textUTF8Length = text.utf8.count
        let endOffset = endOffset ?? textUTF8Length
        guard startOffset >= 0,
              startOffset < endOffset,
              endOffset <= textUTF8Length else {
            return []
        }

        let startUTF8Index = text.utf8.index(
            text.utf8.startIndex,
            offsetBy: startOffset
        )
        guard let startIndex = String.Index(startUTF8Index, within: text) else {
            return []
        }

        var candidates: [LookupPrefixCandidate] = []
        candidates.reserveCapacity(LookupCandidateLimits.maximumPrefixCharacterCount)
        var endIndex = startIndex
        for _ in 0..<LookupCandidateLimits.maximumPrefixCharacterCount {
            guard endIndex < text.endIndex else { break }
            endIndex = text.index(after: endIndex)

            let key = String(text[startIndex..<endIndex])
            let candidateEndOffset = startOffset + key.utf8.count
            guard candidateEndOffset <= endOffset,
                  candidateEndOffset - startOffset
                    <= LookupCandidateLimits.maximumPrefixUTF8Length else {
                break
            }
            candidates.append(
                LookupPrefixCandidate(
                    key: key,
                    normalizedRange: UTF8TextRange(
                        start: startOffset,
                        end: candidateEndOffset
                    )
                )
            )
        }
        return candidates.reversed()
    }
}
