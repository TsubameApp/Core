import Foundation
import Testing
@testable import TsubameCore

@Suite
struct DictionaryRangeScanTests {
    private var fileManager: FileManager { .default }

    @Test func scansArbitrarySelectionAndReturnsHonestOverlappingRanges() throws {
        try withTemporaryDirectory { directory in
            let store = try makeDictionaryStore(in: directory)
            let text = "前文：東海岸、メリーランド州とヴ：後文"
            let request = try ScanLookupRequest(
                text: text,
                range: UTF8TextRange(start: 9, end: 51)
            )

            let results = try DictionaryLookup(store: store).scan(request)

            #expect(results.map(\.sourceRange) == [
                UTF8TextRange(start: 9, end: 18),
                UTF8TextRange(start: 9, end: 12),
                UTF8TextRange(start: 12, end: 18),
                UTF8TextRange(start: 21, end: 42),
                UTF8TextRange(start: 21, end: 39),
                UTF8TextRange(start: 39, end: 42),
                UTF8TextRange(start: 42, end: 45),
            ])
            #expect(results.map { $0.entries.first?.expression } == [
                "東海岸", "東", "海岸", "メリーランド州", "メリーランド", "州", "と",
            ])
        }
    }

    @Test func deinflectsAtEveryLexicalAnchor() throws {
        try withTemporaryDirectory { directory in
            let store = try makeDictionaryStore(in: directory)
            let text = "昨日、食べました。読んだ"

            let results = try DictionaryLookup(store: store).scan(
                ScanLookupRequest(
                    text: text,
                    range: UTF8TextRange(start: 0, end: text.utf8.count)
                )
            )

            #expect(
                results.contains {
                    $0.sourceRange == UTF8TextRange(start: 9, end: 24)
                        && $0.entries.first?.expression == "食べる"
                }
            )
            #expect(
                results.contains {
                    $0.sourceRange == UTF8TextRange(start: 27, end: 36)
                        && $0.entries.first?.expression == "読む"
                }
            )
        }
    }

    @Test func treatsSelectionBoundariesAsHardEvenWhenTheyCutAWord() throws {
        try withTemporaryDirectory { directory in
            let store = try makeDictionaryStore(in: directory)
            let text = "東海岸"

            let results = try DictionaryLookup(store: store).scan(
                ScanLookupRequest(
                    text: text,
                    range: UTF8TextRange(start: 3, end: 9)
                )
            )

            #expect(results.map(\.sourceRange) == [
                UTF8TextRange(start: 3, end: 9),
            ])
            #expect(results.first?.entries.first?.expression == "海岸")
        }
    }

    @Test func mapsNormalizedMatchBackToAbsoluteOriginalRange() throws {
        try withTemporaryDirectory { directory in
            let store = try makeDictionaryStore(in: directory)
            let text = "私はｶﾞｸｾｲです"

            let results = try DictionaryLookup(store: store).scan(
                ScanLookupRequest(
                    text: text,
                    range: UTF8TextRange(start: 6, end: 21)
                )
            )

            #expect(results.first?.sourceRange == UTF8TextRange(start: 6, end: 21))
            #expect(results.first?.entries.first?.expression == "ガクセイ")
        }
    }

    @Test func scansCompatibilitySymbolsWhichNormalizeToLexicalText() throws {
        let entry = makeEntry(id: 1, expression: "㍿")
        let store = RecordingScanStore { keys, _ in
            keys.contains { $0.key.utf8.elementsEqual("㍿".utf8) } ? [entry] : []
        }

        let results = try DictionaryLookup(store: store).scan(
            ScanLookupRequest(
                text: "㍿",
                range: UTF8TextRange(start: 0, end: 3)
            )
        )

        #expect(results.first?.sourceRange == UTF8TextRange(start: 0, end: 3))
        #expect(results.first?.entries.first?.expression == "㍿")
    }

    @Test func skipsGarbageAnchorsAndGloballyDeduplicatesRepeatedKeys() throws {
        let entry = makeEntry(id: 1, expression: "と")
        let store = RecordingScanStore { keys, _ in
            keys.contains { $0.key.utf8.elementsEqual("と".utf8) } ? [entry] : []
        }
        let text = "と、 \nと"

        let results = try DictionaryLookup(store: store).scan(
            ScanLookupRequest(
                text: text,
                range: UTF8TextRange(start: 0, end: text.utf8.count)
            )
        )

        #expect(store.lookupCount == 1)
        #expect(store.receivedBatches.flatMap { $0 }.count { $0.key == "と" } == 1)
        #expect(
            store.receivedBatches.flatMap { $0 }.allSatisfy {
                !($0.key.first?.isWhitespace ?? false)
                    && !$0.key.hasPrefix("、")
            }
        )
        #expect(results.map(\.sourceRange) == [
            UTF8TextRange(start: 0, end: 3),
            UTF8TextRange(start: 8, end: 11),
        ])

        let punctuationStore = RecordingScanStore { _, _ in [] }
        let punctuation = "、 。\n「」"
        let empty = try DictionaryLookup(store: punctuationStore).scan(
            ScanLookupRequest(
                text: punctuation,
                range: UTF8TextRange(start: 0, end: punctuation.utf8.count)
            )
        )
        #expect(empty.isEmpty)
        #expect(punctuationStore.lookupCount == 0)
    }

    @Test func neverGeneratesPrefixesOutsideSelectedRange() throws {
        let entry = makeEntry(id: 1, expression: "東海岸")
        let store = RecordingScanStore { _, _ in [entry] }
        let text = "外東海岸外"

        let results = try DictionaryLookup(store: store).scan(
            ScanLookupRequest(
                text: text,
                range: UTF8TextRange(start: 3, end: 12)
            )
        )

        #expect(store.receivedBatches.flatMap { $0 }.allSatisfy { $0.key != "東海岸外" })
        #expect(results.first?.sourceRange == UTF8TextRange(start: 3, end: 12))
    }

    @Test func usesOneBatchForOrdinaryFragmentAndChunksMoreThanFiveHundredKeys() throws {
        let ordinaryStore = RecordingScanStore { _, _ in [] }
        let ordinary = "東海岸、メリーランド州とヴ"
        _ = try DictionaryLookup(store: ordinaryStore).scan(
            ScanLookupRequest(
                text: ordinary,
                range: UTF8TextRange(start: 0, end: ordinary.utf8.count)
            )
        )
        #expect(ordinaryStore.lookupCount == 1)

        let largeStore = RecordingScanStore { _, _ in [] }
        let large = uniqueCJKText(count: 40)
        _ = try DictionaryLookup(store: largeStore).scan(
            ScanLookupRequest(
                text: large,
                range: UTF8TextRange(start: 0, end: large.utf8.count)
            )
        )
        #expect(largeStore.lookupCount == 2)
        #expect(
            largeStore.receivedBatches.allSatisfy {
                $0.count <= LookupCandidateLimits.maximumLookupKeyCount
            }
        )
    }

    @Test func adaptivelySplitsSaturatedBatches() throws {
        let entry = makeEntry(id: 1, expression: "東")
        let store = RecordingScanStore { keys, _ in
            if keys.count > 1 {
                return (0..<LookupRequestLimits.maximumEntriesPerGroup).map {
                    makeEntry(id: Int64(10_000 + $0), expression: keys[0].key)
                }
            }
            return keys[0].key == "東" ? [entry] : []
        }
        let text = "東海"

        let results = try DictionaryLookup(store: store).scan(
            ScanLookupRequest(
                text: text,
                range: UTF8TextRange(start: 0, end: text.utf8.count)
            )
        )

        #expect(store.lookupCount == 5)
        #expect(
            results.contains {
                $0.sourceRange == UTF8TextRange(start: 0, end: 3)
                    && $0.entries.first?.expression == "東"
            }
        )
    }

    @Test func appliesGroupAndEntryLimitsAfterStableRangeOrdering() throws {
        let entries = [
            makeEntry(id: 1, expression: "東"),
            makeEntry(id: 2, expression: "東"),
            makeEntry(id: 3, expression: "海"),
        ]
        let store = RecordingScanStore { keys, _ in
            entries.filter { entry in
                keys.contains { key in
                    entry.matches.contains {
                        $0.key.utf8.elementsEqual(key.key.utf8)
                    }
                }
            }
        }
        let text = "東海"

        let results = try DictionaryLookup(store: store).scan(
            ScanLookupRequest(
                text: text,
                range: UTF8TextRange(start: 0, end: text.utf8.count),
                resultGroupLimit: 1,
                entriesPerGroupLimit: 1
            )
        )

        #expect(results.count == 1)
        #expect(results[0].sourceRange == UTF8TextRange(start: 0, end: 3))
        #expect(results[0].entries.map(\.id) == [1])
    }

    @Test func rejectsPathologicalCandidateAndBatchWork() throws {
        let text = uniqueCJKText(count: 300)
        let emptyStore = RecordingScanStore { _, _ in [] }

        #expect(
            throws: DictionaryLookupError.scanUniqueKeyLimitExceeded(
                actual: LookupCandidateLimits.maximumScanUniqueLookupKeyCount + 1,
                maximum: LookupCandidateLimits.maximumScanUniqueLookupKeyCount
            )
        ) {
            _ = try DictionaryLookup(store: emptyStore).scan(
                ScanLookupRequest(
                    text: text,
                    range: UTF8TextRange(start: 0, end: text.utf8.count)
                )
            )
        }

        let saturatedStore = RecordingScanStore { keys, _ in
            (0..<LookupRequestLimits.maximumEntriesPerGroup).map {
                makeEntry(id: Int64($0), expression: keys[0].key)
            }
        }
        let enoughKeysToExhaustSplits = uniqueCJKText(count: 8)
        #expect(
            throws: DictionaryLookupError.scanBatchLimitExceeded(
                actual: LookupCandidateLimits.maximumScanLookupBatchCount + 1,
                maximum: LookupCandidateLimits.maximumScanLookupBatchCount
            )
        ) {
            _ = try DictionaryLookup(store: saturatedStore).scan(
                ScanLookupRequest(
                    text: enoughKeysToExhaustSplits,
                    range: UTF8TextRange(
                        start: 0,
                        end: enoughKeysToExhaustSplits.utf8.count
                    )
                )
            )
        }
    }

    private func makeDictionaryStore(in directory: URL) throws -> SQLiteDictionaryStore {
        let archive = directory.appending(path: "dictionary.zip")
        let database = directory.appending(path: "dictionary.sqlite")
        try makeZIP([
            .file(
                "index.json",
                #"{"title":"Range Scan Test","format":3,"revision":"1"}"#
            ),
            .file(
                "term_bank_1.json",
                #"[["東海岸","とうかいがん","","",10,["east coast"],1,""],["東","ひがし","","",9,["east"],2,""],["海岸","かいがん","","",8,["coast"],3,""],["メリーランド州","メリーランドしゅう","","",7,["Maryland"],4,""],["メリーランド","メリーランド","","",6,["Maryland"],5,""],["州","しゅう","","",5,["state"],6,""],["と","と","","",4,["and"],7,""],["食べる","たべる","v1","v1",3,["eat"],8,""],["読む","よむ","v5m","v5",2,["read"],9,""],["ガクセイ","がくせい","","",1,["student"],10,""]]"#
            ),
        ]).write(to: archive)
        _ = try YomitanSQLiteDictionaryImporter(
            temporaryRoot: directory.appending(path: "temporary")
        ).import(
            from: DictionaryImportSource(url: archive),
            to: database
        )
        return try SQLiteDictionaryStore(databaseURL: database)
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory.appending(
            path: "TsubameRangeScanTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try body(directory)
    }
}

private final class RecordingScanStore: DictionaryStore {
    private(set) var lookupCount = 0
    private(set) var receivedBatches: [[DictionaryLookupKey]] = []
    private let handler: ([DictionaryLookupKey], Int) throws -> [DictionaryEntry]

    init(handler: @escaping ([DictionaryLookupKey], Int) throws -> [DictionaryEntry]) {
        self.handler = handler
    }

    func lookup(
        keys: [DictionaryLookupKey],
        limit: Int
    ) throws -> [DictionaryEntry] {
        lookupCount += 1
        receivedBatches.append(keys)
        return try handler(keys, limit)
    }
}

private func uniqueCJKText(count: Int) -> String {
    String(
        (0..<count).compactMap {
            Unicode.Scalar(0x4E00 + $0).map(Character.init)
        }
    )
}

private func makeEntry(id: Int64, expression: String) -> DictionaryEntry {
    DictionaryEntry(
        id: id,
        expression: expression,
        reading: "",
        definitionTags: nil,
        rules: "",
        score: 0,
        sequence: -1,
        termTags: "",
        matches: [
            DictionaryEntryMatch(key: expression, keyType: .expression),
        ],
        definitions: []
    )
}
