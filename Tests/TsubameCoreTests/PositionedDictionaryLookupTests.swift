import Foundation
import Testing
@testable import TsubameCore

@Suite
struct PositionedDictionaryLookupTests {
    private var fileManager: FileManager { .default }

    @Test func findsLongestDictionaryPrefixInSentence() throws {
        try withTemporaryDirectory { directory in
            let store = try makeDictionaryStore(in: directory)
            let lookup = DictionaryLookup(store: store)
            let request = try PositionedLookupRequest(
                text: "私はご飯を食べる。",
                position: 15
            )

            let result = try lookup.lookup(request)

            #expect(result.sourceRange == UTF8TextRange(start: 15, end: 24))
            #expect(result.entries.map(\.expression) == ["食べる"])
        }
    }

    @Test func mapsNormalizedMatchBackToOriginalSentence() throws {
        try withTemporaryDirectory { directory in
            let store = try makeDictionaryStore(in: directory)
            let lookup = DictionaryLookup(store: store)
            let request = try PositionedLookupRequest(
                text: "私はｶﾞｸｾｲです。",
                position: 6
            )

            let result = try lookup.lookup(request)

            #expect(result.sourceRange == UTF8TextRange(start: 6, end: 21))
            #expect(result.entries.map(\.expression) == ["ガクセイ"])
        }
    }

    @Test func batchesCandidatesAndChoosesLongestMatchingPrefix() throws {
        let longerEntry = makeEntry(id: 1, expression: "食べ")
        let shorterEntry = makeEntry(id: 2, expression: "食")
        let store = RecordingDictionaryStore(entries: [longerEntry, shorterEntry])
        let lookup = DictionaryLookup(store: store)
        let request = try PositionedLookupRequest(text: "食べる。", position: 0)

        let result = try lookup.lookup(request)

        #expect(store.lookupCount == 1)
        for exactKey in ["食べる。", "食べる", "食べ", "食"] {
            #expect(
                store.receivedLookupKeys.contains {
                    $0.key == exactKey && $0.requiredRules == nil
                }
            )
        }
        #expect(result.sourceRange == UTF8TextRange(start: 0, end: 6))
        #expect(result.entries.map(\.expression) == ["食べ"])
    }

    @Test func returnsEmptyRangeAtPositionWhenNothingMatches() throws {
        let store = RecordingDictionaryStore(entries: [])
        let lookup = DictionaryLookup(store: store)
        let request = try PositionedLookupRequest(text: "未知。", position: 0)

        let result = try lookup.lookup(request)

        #expect(result.sourceRange == UTF8TextRange(start: 0, end: 0))
        #expect(result.entries.isEmpty)
        #expect(store.lookupCount == 1)
    }

    @Test func deinflectsRequiredJapaneseFormsAndKeepsSurfaceRange() throws {
        try withTemporaryDirectory { directory in
            let store = try makeDictionaryStore(in: directory)
            let lookup = DictionaryLookup(store: store)
            let cases = [
                ("食べました", "食べる"),
                ("食べなかった", "食べる"),
                ("読んだ", "読む"),
                ("書いた", "書く"),
                ("話した", "話す"),
            ]

            for (surface, lemma) in cases {
                let result = try lookup.lookup(
                    PositionedLookupRequest(text: surface + "。", position: 0)
                )
                #expect(
                    result.sourceRange == UTF8TextRange(
                        start: 0,
                        end: surface.utf8.count
                    )
                )
                #expect(result.entries.first?.expression == lemma)
            }
        }
    }

    @Test func ranksExactBeforeDeinflectedForSameSurface() throws {
        let exact = makeEntry(id: 1, expression: "食べました", rules: "")
        let lemma = makeEntry(id: 2, expression: "食べる", rules: "v1")
        let store = RecordingDictionaryStore(entries: [lemma, exact])
        let lookup = DictionaryLookup(store: store)

        let result = try lookup.lookup(
            PositionedLookupRequest(text: "食べました。", position: 0)
        )

        #expect(result.entries.map(\.expression) == ["食べました", "食べる"])
    }

    @Test func ranksLongerDeinflectedSurfaceBeforeShorterExactSurface() throws {
        let shorterExact = makeEntry(id: 1, expression: "食", rules: "")
        let longerLemma = makeEntry(id: 2, expression: "食べる", rules: "v1")
        let store = RecordingDictionaryStore(entries: [shorterExact, longerLemma])
        let lookup = DictionaryLookup(store: store)

        let result = try lookup.lookup(
            PositionedLookupRequest(text: "食べました。", position: 0)
        )

        #expect(result.sourceRange == UTF8TextRange(start: 0, end: 15))
        #expect(result.entries.map(\.expression) == ["食べる"])
    }

    @Test func returnsWithoutQueryingAtEndOfText() throws {
        let store = RecordingDictionaryStore(entries: [])
        let lookup = DictionaryLookup(store: store)
        let request = try PositionedLookupRequest(text: "食べる", position: 9)

        let result = try lookup.lookup(request)

        #expect(result.sourceRange == UTF8TextRange(start: 9, end: 9))
        #expect(result.entries.isEmpty)
        #expect(store.lookupCount == 0)
    }

    @Test func boundsGeneratedPrefixCount() throws {
        let store = RecordingDictionaryStore(entries: [])
        let lookup = DictionaryLookup(store: store)
        let request = try PositionedLookupRequest(
            text: String(repeating: "あ", count: 40),
            position: 0
        )

        _ = try lookup.lookup(request)

        #expect(store.receivedKeys.count == LookupCandidateLimits.maximumPrefixCharacterCount)
        #expect(store.receivedKeys.first?.count == 32)
        #expect(store.receivedKeys.last == "あ")
    }

    @Test func boundsGeneratedPrefixUTF8Length() throws {
        let store = RecordingDictionaryStore(entries: [])
        let lookup = DictionaryLookup(store: store)
        let request = try PositionedLookupRequest(
            text: String(repeating: "👨‍👩‍👧‍👦", count: 20),
            position: 0
        )

        _ = try lookup.lookup(request)

        #expect(!store.receivedKeys.isEmpty)
        #expect(
            store.receivedKeys.allSatisfy {
                $0.utf8.count <= LookupCandidateLimits.maximumPrefixUTF8Length
            }
        )
    }

    private func makeDictionaryStore(in directory: URL) throws -> SQLiteDictionaryStore {
        let archive = directory.appending(path: "dictionary.zip")
        let database = directory.appending(path: "dictionary.sqlite")
        try makeZIP([
            .file(
                "index.json",
                #"{"title":"Positioned Lookup Test","format":3,"revision":"1"}"#
            ),
            .file(
                "term_bank_1.json",
                #"[["食べる","たべる","v1","v1",10,["to eat"],1,""],["読む","よむ","v5m","v5",9,["to read"],2,""],["書く","かく","v5k","v5",8,["to write"],3,""],["話す","はなす","v5s","v5",7,["to speak"],4,""],["食","しょく","","",5,["food"],5,""],["ガクセイ","がくせい","","",3,["student"],6,""]]"#
            )
        ]).write(to: archive)

        _ = try YomitanSQLiteDictionaryImporter(
            temporaryRoot: directory.appending(path: "temporary")
        ).import(
            from: DictionaryImportSource(url: archive),
            to: database
        )
        return try SQLiteDictionaryStore(databaseURL: database)
    }

    private func makeEntry(
        id: Int64,
        expression: String,
        rules: String = ""
    ) -> DictionaryEntry {
        DictionaryEntry(
            id: id,
            expression: expression,
            reading: "",
            definitionTags: nil,
            rules: rules,
            score: 0,
            sequence: -1,
            termTags: "",
            matches: [
                DictionaryEntryMatch(key: expression, keyType: .expression)
            ],
            definitions: []
        )
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory.appending(
            path: "TsubamePositionedLookupTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try body(directory)
    }
}

private final class RecordingDictionaryStore: DictionaryStore {
    private(set) var lookupCount = 0
    private(set) var receivedKeys: [String] = []
    private(set) var receivedLookupKeys: [DictionaryLookupKey] = []
    private let entries: [DictionaryEntry]

    init(entries: [DictionaryEntry]) {
        self.entries = entries
    }

    func lookup(
        keys: [DictionaryLookupKey],
        limit: Int
    ) throws -> [DictionaryEntry] {
        lookupCount += 1
        receivedLookupKeys = keys
        receivedKeys = keys.map(\.key)
        return Array(entries.prefix(limit))
    }
}
