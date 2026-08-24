import Foundation

enum LookupCandidateLimits {
    static let maximumPrefixCharacterCount = 32
    static let maximumPrefixUTF8Length = 256
}

struct LookupPrefixCandidate: Sendable, Equatable {
    let key: String
    let normalizedRange: UTF8TextRange
}

struct PrefixCandidateGenerator: Sendable {
    func candidates(
        in text: String,
        fromUTF8Offset startOffset: Int
    ) -> [LookupPrefixCandidate] {
        guard startOffset >= 0, startOffset < text.utf8.count else { return [] }

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
            let endOffset = startOffset + key.utf8.count
            guard endOffset - startOffset <= LookupCandidateLimits.maximumPrefixUTF8Length else {
                break
            }
            candidates.append(
                LookupPrefixCandidate(
                    key: key,
                    normalizedRange: UTF8TextRange(
                        start: startOffset,
                        end: endOffset
                    )
                )
            )
        }
        return candidates.reversed()
    }
}
