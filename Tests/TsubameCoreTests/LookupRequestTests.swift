import Testing
@testable import TsubameCore

@Suite
struct LookupRequestTests {
    @Test func createsPositionedRequestWithUTF8BytePosition() throws {
        let request = try PositionedLookupRequest(
            text: "私は食べる",
            position: 6,
            resultLimit: 25
        )

        #expect(request.position == 6)
        #expect(request.resultLimit == 25)
    }

    @Test func permitsPositionAtEndOfText() throws {
        let text = "食べる"
        let request = try PositionedLookupRequest(
            text: text,
            position: text.utf8.count
        )

        #expect(request.position == 9)
    }

    @Test func createsScanRequestForPartOfSentence() throws {
        let text = "私はご飯を食べる。"
        let request = try ScanLookupRequest(
            text: text,
            range: UTF8TextRange(start: 6, end: 24),
            resultGroupLimit: 20,
            entriesPerGroupLimit: 30
        )

        #expect(request.range == UTF8TextRange(start: 6, end: 24))
        #expect(request.resultGroupLimit == 20)
        #expect(request.entriesPerGroupLimit == 30)
    }

    @Test func lookupResultKeepsOriginalUTF8SourceRange() {
        let result = LookupResult(
            sourceRange: UTF8TextRange(start: 6, end: 15),
            entries: []
        )

        #expect(result.sourceRange == UTF8TextRange(start: 6, end: 15))
        #expect(result.entries.isEmpty)
    }

    @Test func rejectsPositionInsideMultibyteCharacter() {
        #expect(throws: LookupRequestError.offsetIsNotCharacterBoundary(1)) {
            _ = try PositionedLookupRequest(text: "食べる", position: 1)
        }
    }

    @Test func rejectsOffsetInsideExtendedGraphemeCluster() {
        #expect(throws: LookupRequestError.offsetIsNotCharacterBoundary(1)) {
            _ = try PositionedLookupRequest(text: "e\u{301}語", position: 1)
        }
    }

    @Test func rejectsOutOfBoundsPosition() {
        #expect(
            throws: LookupRequestError.positionOutOfBounds(
                position: 10,
                textUTF8Length: 9
            )
        ) {
            _ = try PositionedLookupRequest(text: "食べる", position: 10)
        }
    }

    @Test func rejectsInvalidScanRanges() {
        #expect(
            throws: LookupRequestError.rangeOutOfBounds(
                range: UTF8TextRange(start: 6, end: 3),
                textUTF8Length: 9
            )
        ) {
            _ = try ScanLookupRequest(
                text: "食べる",
                range: UTF8TextRange(start: 6, end: 3)
            )
        }

        #expect(throws: LookupRequestError.emptyScanRange) {
            _ = try ScanLookupRequest(
                text: "食べる",
                range: UTF8TextRange(start: 3, end: 3)
            )
        }

        #expect(throws: LookupRequestError.offsetIsNotCharacterBoundary(2)) {
            _ = try ScanLookupRequest(
                text: "食べる",
                range: UTF8TextRange(start: 0, end: 2)
            )
        }
    }

    @Test func rejectsEmptyAndOversizedText() {
        #expect(throws: LookupRequestError.emptyText) {
            _ = try PositionedLookupRequest(text: "", position: 0)
        }

        let text = String(
            repeating: "a",
            count: LookupRequestLimits.maximumTextUTF8Length + 1
        )
        #expect(
            throws: LookupRequestError.textTooLong(
                actual: LookupRequestLimits.maximumTextUTF8Length + 1,
                maximum: LookupRequestLimits.maximumTextUTF8Length
            )
        ) {
            _ = try PositionedLookupRequest(text: text, position: 0)
        }
    }

    @Test func rejectsOversizedScanRange() {
        let text = String(
            repeating: "a",
            count: LookupRequestLimits.maximumScanRangeUTF8Length + 1
        )
        #expect(
            throws: LookupRequestError.scanRangeTooLong(
                actual: LookupRequestLimits.maximumScanRangeUTF8Length + 1,
                maximum: LookupRequestLimits.maximumScanRangeUTF8Length
            )
        ) {
            _ = try ScanLookupRequest(
                text: text,
                range: UTF8TextRange(start: 0, end: text.utf8.count)
            )
        }
    }

    @Test func rejectsInvalidResultLimits() {
        #expect(throws: LookupRequestError.invalidResultLimit(0)) {
            _ = try PositionedLookupRequest(
                text: "食べる",
                position: 0,
                resultLimit: 0
            )
        }
        #expect(
            throws: LookupRequestError.resultLimitTooLarge(
                actual: LookupRequestLimits.maximumEntriesPerGroup + 1,
                maximum: LookupRequestLimits.maximumEntriesPerGroup
            )
        ) {
            _ = try PositionedLookupRequest(
                text: "食べる",
                position: 0,
                resultLimit: LookupRequestLimits.maximumEntriesPerGroup + 1
            )
        }
        #expect(throws: LookupRequestError.invalidResultGroupLimit(0)) {
            _ = try ScanLookupRequest(
                text: "食べる",
                range: UTF8TextRange(start: 0, end: 9),
                resultGroupLimit: 0
            )
        }
        #expect(
            throws: LookupRequestError.resultGroupLimitTooLarge(
                actual: LookupRequestLimits.maximumResultGroups + 1,
                maximum: LookupRequestLimits.maximumResultGroups
            )
        ) {
            _ = try ScanLookupRequest(
                text: "食べる",
                range: UTF8TextRange(start: 0, end: 9),
                resultGroupLimit: LookupRequestLimits.maximumResultGroups + 1
            )
        }
    }
}
