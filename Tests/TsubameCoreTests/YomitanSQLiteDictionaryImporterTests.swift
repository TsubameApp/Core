import Foundation
import Testing
@testable import TsubameCore

@Suite
struct YomitanSQLiteDictionaryImporterTests {
    private var fileManager: FileManager { .default }

    @Test func importsAllSupportedBanksIntoOneQueryableDatabase() throws {
        try withTemporaryDirectory { directory in
            let archive = directory.appending(path: "dictionary.zip")
            let database = directory.appending(path: "dictionary.sqlite")
            try makeDictionaryArchive().write(to: archive)

            let result = try YomitanSQLiteDictionaryImporter(
                temporaryRoot: directory.appending(path: "temporary")
            ).import(
                from: DictionaryImportSource(url: archive),
                to: database
            )

            #expect(result.databaseURL == database)
            #expect(result.preview.index.title == "SQLite Test")
            #expect(result.preview.totalEntries == 2)
            #expect(result.preview.totalTermMetadata == 2)
            #expect(result.preview.totalKanji == 1)
            #expect(result.preview.totalKanjiMetadata == 1)
            #expect(result.preview.totalTags == 1)
            #expect(result.definitionCount == 3)
            #expect(result.lookupKeyCount == 4)

            let connection = try SQLiteConnection(url: database, mode: .readOnly)
            defer { try? connection.close() }

            #expect(try integer("SELECT COUNT(*) FROM term_entry", connection: connection) == 2)
            #expect(try integer("SELECT COUNT(*) FROM term_definition", connection: connection) == 3)
            #expect(try integer("SELECT COUNT(*) FROM term_metadata", connection: connection) == 2)
            #expect(try integer("SELECT COUNT(*) FROM kanji_entry", connection: connection) == 1)
            #expect(try integer("SELECT COUNT(*) FROM kanji_metadata", connection: connection) == 1)
            #expect(try integer("SELECT COUNT(*) FROM tag", connection: connection) == 1)
            #expect(try integer("PRAGMA user_version", connection: connection) == 1)

            let lookup = try connection.prepare(
                """
                SELECT term_entry.expression, lookup_key.key_type
                FROM lookup_key
                JOIN term_entry ON term_entry.id = lookup_key.entry_id
                WHERE lookup_key.key = ?
                """
            )
            try lookup.bind("たべる", at: 1)
            #expect(try lookup.step() == .row)
            #expect(lookup.string(at: 0) == "食べる")
            #expect(lookup.string(at: 1) == "reading")
            #expect(try lookup.step() == .done)
            try lookup.finalize()

            let structured = try connection.prepare(
                """
                SELECT content_json FROM term_definition
                WHERE kind = 'object'
                """
            )
            #expect(try structured.step() == .row)
            let structuredData = try #require(structured.data(at: 0))
            let structuredJSON = try JSONDecoder().decode(
                YomitanGlossaryItem.self,
                from: structuredData
            )
            #expect(
                structuredJSON == .object([
                    "type": .string("structured-content"),
                    "content": .object(["tag": .string("b"), "content": .string("bold")])
                ])
            )
            try structured.finalize()

            let integrity = try connection.prepare("PRAGMA integrity_check")
            #expect(try integrity.step() == .row)
            #expect(integrity.string(at: 0) == "ok")
            try integrity.finalize()
        }
    }

    @Test func removesDatabaseWhenALaterBankFailsInsideTransaction() throws {
        try withTemporaryDirectory { directory in
            let archive = directory.appending(path: "broken.zip")
            let database = directory.appending(path: "dictionary.sqlite")
            try makeZIP([
                .file("index.json", #"{"title":"Broken","format":3,"revision":"1"}"#),
                .file("term_bank_1.json", #"[["食べる","たべる","","v1",0,["eat"],1,""]]"#),
                .file("term_bank_2.json", "not valid JSON")
            ]).write(to: archive)

            #expect(throws: (any Error).self) {
                try YomitanSQLiteDictionaryImporter(
                    temporaryRoot: directory.appending(path: "temporary")
                ).import(
                    from: DictionaryImportSource(url: archive),
                    to: database
                )
            }

            #expect(!fileManager.fileExists(atPath: database.path))
            #expect(!fileManager.fileExists(atPath: database.path + "-journal"))
        }
    }

    @Test func refusesToOverwriteExistingDatabase() throws {
        try withTemporaryDirectory { directory in
            let archive = directory.appending(path: "dictionary.zip")
            let database = directory.appending(path: "existing.sqlite")
            let existing = Data("keep me".utf8)
            try makeDictionaryArchive().write(to: archive)
            try existing.write(to: database)

            #expect(throws: DictionaryImportError.self) {
                try YomitanSQLiteDictionaryImporter(temporaryRoot: directory).import(
                    from: DictionaryImportSource(url: archive),
                    to: database
                )
            }
            #expect(try Data(contentsOf: database) == existing)
        }
    }

    private func makeDictionaryArchive() -> Data {
        makeZIP([
            .file(
                "index.json",
                #"{"title":"SQLite Test","format":3,"revision":"1","sequenced":true,"sourceLanguage":"ja","targetLanguage":"en"}"#
            ),
            .file(
                "term_bank_1.json",
                #"[["食べる","たべる","v1","v1",10,["to eat",{"type":"structured-content","content":{"tag":"b","content":"bold"}}],42,"common"],["読む","よむ","v5m","v5",5,["to read"],43,""]]"#
            ),
            .file(
                "term_meta_bank_1.json",
                #"[["食べる","freq",{"value":10}],["食べる","pitch",{"reading":"たべる","pitches":[{"position":2}]}]]"#
            ),
            .file(
                "kanji_bank_1.json",
                #"[["亜","ア","つ.ぐ","jouyou",["Asia"],{"strokes":"7"}]]"#
            ),
            .file(
                "kanji_meta_bank_1.json",
                #"[["亜","freq",{"value":1509}]]"#
            ),
            .file(
                "tag_bank_1.json",
                #"[["common","frequency",1,"Common term",5]]"#
            )
        ])
    }

    private func integer(_ sql: String, connection: SQLiteConnection) throws -> Int64 {
        let statement = try connection.prepare(sql)
        defer { statement.finalizeIgnoringErrors() }
        guard try statement.step() == .row else {
            Issue.record("Expected one row for \(sql)")
            return -1
        }
        let result = statement.integer(at: 0)
        try statement.finalize()
        return result
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory.appending(
            path: "TsubameSQLiteImportTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try body(directory)
    }
}
