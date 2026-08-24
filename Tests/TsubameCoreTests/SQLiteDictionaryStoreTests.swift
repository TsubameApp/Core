import Foundation
import Testing
@testable import TsubameCore

@Suite
struct SQLiteDictionaryStoreTests {
    private var fileManager: FileManager { .default }

    @Test func looksUpExpressionsReadingsAndDefinitionsInOneInstalledDatabase() throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            let store = try SQLiteDictionaryStore(databaseURL: database)

            let entries = try store.lookup(
                keys: ["食べる", "たべる", "食べる"],
                limit: 10
            )

            let entry = try #require(entries.first)
            #expect(entries.count == 1)
            #expect(entry.expression == "食べる")
            #expect(entry.reading == "たべる")
            #expect(entry.definitionTags == "v1")
            #expect(entry.rules == "v1")
            #expect(entry.score == 10)
            #expect(entry.sequence == 42)
            #expect(entry.termTags == "common")
            #expect(entry.matches == [
                DictionaryEntryMatch(key: "食べる", keyType: .expression),
                DictionaryEntryMatch(key: "たべる", keyType: .reading)
            ])
            #expect(entry.definitions.count == 2)
            #expect(entry.definitions[0].position == 0)
            #expect(entry.definitions[0].kind == "text")
            #expect(entry.definitions[0].text == "to eat")
            #expect(entry.definitions[1].position == 1)
            #expect(entry.definitions[1].kind == "object")
            #expect(entry.definitions[1].text == nil)

            let structured = try JSONDecoder().decode(
                YomitanGlossaryItem.self,
                from: entry.definitions[1].contentJSON
            )
            #expect(
                structured == .object([
                    "type": .string("structured-content"),
                    "content": .object([
                        "tag": .string("b"),
                        "content": .string("bold")
                    ])
                ])
            )
        }
    }

    @Test func performsOneBatchedLookupAndKeepsRequestedKeyOrder() throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            let store = try SQLiteDictionaryStore(databaseURL: database)

            let entries = try store.lookup(keys: ["よむ", "食べる"], limit: 10)

            #expect(entries.map(\.expression) == ["読む", "食べる"])
            #expect(entries[0].matches == [
                DictionaryEntryMatch(key: "よむ", keyType: .reading)
            ])
            #expect(entries[1].matches == [
                DictionaryEntryMatch(key: "食べる", keyType: .expression)
            ])
        }
    }

    @Test func returnsEmptyResultsForUnknownOrEmptyKeys() throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            let store = try SQLiteDictionaryStore(databaseURL: database)

            #expect(try store.lookup(keys: ["missing"], limit: 10).isEmpty)
            #expect(try store.lookup(keys: ["", ""], limit: 10).isEmpty)
        }
    }

    @Test func looksUpRawAndNormalizedKeyVariants() throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            let store = try SQLiteDictionaryStore(databaseURL: database)

            let normalizedMatch = try store.lookup(keys: ["ｶﾞｸｾｲ"], limit: 10)
            #expect(normalizedMatch.map(\.expression) == ["ガクセイ"])
            #expect(normalizedMatch.first?.matches == [
                DictionaryEntryMatch(key: "ガクセイ", keyType: .expression)
            ])

            let composedReadingMatch = try store.lookup(
                keys: ["か\u{3099}くせい"],
                limit: 10
            )
            #expect(composedReadingMatch.map(\.expression) == ["ガクセイ"])
            #expect(composedReadingMatch.first?.matches == [
                DictionaryEntryMatch(key: "がくせい", keyType: .reading)
            ])

            let rawCompatibilityMatch = try store.lookup(keys: ["㍿"], limit: 10)
            #expect(rawCompatibilityMatch.map(\.expression) == ["㍿"])
        }
    }

    @Test func respectsEntryLimit() throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            let store = try SQLiteDictionaryStore(databaseURL: database)

            let entries = try store.lookup(keys: ["たべる", "よむ"], limit: 1)

            #expect(entries.count == 1)
            #expect(entries[0].expression == "食べる")
        }
    }

    @Test func rejectsInvalidEntryLimits() throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            let store = try SQLiteDictionaryStore(databaseURL: database)

            #expect(throws: DictionaryStoreError.invalidLimit(0)) {
                _ = try store.lookup(keys: ["食べる"], limit: 0)
            }
            #expect(
                throws: DictionaryStoreError.resultLimitTooLarge(
                    actual: 501,
                    maximum: 500
                )
            ) {
                _ = try store.lookup(keys: ["食べる"], limit: 501)
            }
        }
    }

    @Test func rejectsUnsupportedDictionarySchema() throws {
        try withTemporaryDirectory { directory in
            let database = directory.appending(path: "old.sqlite")
            let connection = try SQLiteConnection(url: database)
            try connection.execute("PRAGMA user_version = 1")
            try connection.close()

            #expect(
                throws: DictionaryStoreError.unsupportedSchemaVersion(
                    actual: 1,
                    expected: DictionaryDatabaseSchema.currentVersion
                )
            ) {
                _ = try SQLiteDictionaryStore(databaseURL: database)
            }
        }
    }

    private func makeDictionaryDatabase(in directory: URL) throws -> URL {
        let archive = directory.appending(path: "dictionary.zip")
        let database = directory.appending(path: "dictionary.sqlite")
        try makeZIP([
            .file(
                "index.json",
                #"{"title":"Lookup Test","format":3,"revision":"1"}"#
            ),
            .file(
                "term_bank_1.json",
                #"[["食べる","たべる","v1","v1",10,["to eat",{"type":"structured-content","content":{"tag":"b","content":"bold"}}],42,"common"],["読む","よむ","v5m","v5",5,["to read"],43,""],["ガクセイ","がくせい","","",3,["student"],44,""],["㍿","","","",1,["company"],45,""]]"#
            )
        ]).write(to: archive)

        _ = try YomitanSQLiteDictionaryImporter(
            temporaryRoot: directory.appending(path: "temporary")
        ).import(
            from: DictionaryImportSource(url: archive),
            to: database
        )
        return database
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory.appending(
            path: "TsubameDictionaryStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try body(directory)
    }
}
