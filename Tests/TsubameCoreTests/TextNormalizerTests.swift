import Testing
@testable import TsubameCore

@Suite
struct TextNormalizerTests {
    private let normalizer = TextNormalizer()

    @Test func normalizesHalfWidthKanaAndMapsBackToOriginalBytes() throws {
        let normalized = normalizer.normalize("ｶﾞｸｾｲ")

        #expect(normalized.text == "ガクセイ")
        #expect(normalized.originalUTF8Length == 15)
        #expect(normalized.normalizedUTF8Length == 12)
        #expect(
            try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 0, end: 3)
            ) == UTF8TextRange(start: 0, end: 6)
        )
        #expect(
            try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 3, end: 12)
            ) == UTF8TextRange(start: 6, end: 15)
        )
    }

    @Test func composesCombiningDakutenAndPreservesSourceRange() throws {
        let normalized = normalizer.normalize("か\u{3099}く")

        #expect(normalized.text == "がく")
        #expect(
            try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 0, end: 3)
            ) == UTF8TextRange(start: 0, end: 6)
        )
    }

    @Test func mapsSentenceSelectionInBothDirections() throws {
        let normalized = normalizer.normalize("私はｶﾞｸｾｲです")
        let originalRange = UTF8TextRange(start: 6, end: 21)
        let normalizedRange = UTF8TextRange(start: 6, end: 18)

        #expect(normalized.text == "私はガクセイです")
        #expect(
            try normalized.normalizedUTF8Range(forOriginalUTF8Range: originalRange)
                == normalizedRange
        )
        #expect(
            try normalized.originalUTF8Range(forNormalizedUTF8Range: normalizedRange)
                == originalRange
        )
    }

    @Test func mapsPartOfCompatibilityExpansionToWholeOriginalCharacter() throws {
        let normalized = normalizer.normalize("㍿です")

        #expect(normalized.text == "株式会社です")
        #expect(
            try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 0, end: 3)
            ) == UTF8TextRange(start: 0, end: 3)
        )
        #expect(
            try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 3, end: 12)
            ) == UTF8TextRange(start: 0, end: 3)
        )
    }

    @Test func leavesOrdinaryJapaneseTextUnchanged() throws {
        let text = "私はご飯を食べる。"
        let normalized = normalizer.normalize(text)
        let entireRange = UTF8TextRange(start: 0, end: text.utf8.count)

        #expect(normalized.text == text)
        #expect(
            try normalized.normalizedUTF8Range(forOriginalUTF8Range: entireRange)
                == entireRange
        )
        #expect(
            try normalized.originalUTF8Range(forNormalizedUTF8Range: entireRange)
                == entireRange
        )
    }

    @Test func matchesWholeStringCompatibilityNormalization() {
        for text in ["ｶﾞｸｾｲ", "か\u{3099}く", "㍿ＡＢＣ", "私はご飯を食べる。"] {
            let expected = text
                .precomposedStringWithCompatibilityMapping
                .precomposedStringWithCanonicalMapping

            #expect(normalizer.normalize(text).text == expected)
        }
    }

    @Test func mapsOriginalCharacterBoundariesToNormalizedOffsets() throws {
        let normalized = normalizer.normalize("AｶﾞB")

        #expect(try normalized.normalizedUTF8Offset(forOriginalUTF8Offset: 0) == 0)
        #expect(try normalized.normalizedUTF8Offset(forOriginalUTF8Offset: 1) == 1)
        #expect(try normalized.normalizedUTF8Offset(forOriginalUTF8Offset: 7) == 4)
        #expect(try normalized.normalizedUTF8Offset(forOriginalUTF8Offset: 8) == 5)
    }

    @Test func handlesEmptyTextAndEmptyBoundaryRange() throws {
        let normalized = normalizer.normalize("")

        #expect(normalized.text.isEmpty)
        #expect(try normalized.normalizedUTF8Offset(forOriginalUTF8Offset: 0) == 0)
        #expect(
            try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 0, end: 0)
            ) == UTF8TextRange(start: 0, end: 0)
        )
    }

    @Test func rejectsInvalidOriginalCoordinates() throws {
        let normalized = normalizer.normalize("食べる")

        #expect(
            throws: TextNormalizationMappingError.originalOffsetOutOfBounds(
                offset: 10,
                length: 9
            )
        ) {
            _ = try normalized.normalizedUTF8Offset(forOriginalUTF8Offset: 10)
        }
        #expect(
            throws: TextNormalizationMappingError.originalOffsetIsNotCharacterBoundary(1)
        ) {
            _ = try normalized.normalizedUTF8Offset(forOriginalUTF8Offset: 1)
        }
        #expect(
            throws: TextNormalizationMappingError.originalRangeOutOfBounds(
                range: UTF8TextRange(start: 6, end: 3),
                length: 9
            )
        ) {
            _ = try normalized.normalizedUTF8Range(
                forOriginalUTF8Range: UTF8TextRange(start: 6, end: 3)
            )
        }
    }

    @Test func rejectsInvalidNormalizedCoordinates() throws {
        let normalized = normalizer.normalize("㍿")

        #expect(
            throws: TextNormalizationMappingError.normalizedRangeOutOfBounds(
                range: UTF8TextRange(start: 0, end: 13),
                length: 12
            )
        ) {
            _ = try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 0, end: 13)
            )
        }
        #expect(
            throws: TextNormalizationMappingError.normalizedOffsetIsNotCharacterBoundary(1)
        ) {
            _ = try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 1, end: 3)
            )
        }
        #expect(
            throws: TextNormalizationMappingError.normalizedOffsetHasNoOriginalBoundary(3)
        ) {
            _ = try normalized.originalUTF8Range(
                forNormalizedUTF8Range: UTF8TextRange(start: 3, end: 3)
            )
        }
    }
}
