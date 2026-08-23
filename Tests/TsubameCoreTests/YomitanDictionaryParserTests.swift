import Foundation
import Testing
@testable import TsubameCore

@Suite
struct YomitanDictionaryParserTests {
    private var parser: YomitanDictionaryParser { YomitanDictionaryParser() }
    private var fileManager: FileManager { FileManager.default }

    @Test func parsesDictionaryDirectory() throws {
        try withTemporaryDirectory { directory in
            try write(
                #"{"title":"Test Dictionary","format":3,"revision":"1","sequenced":true}"#,
                to: directory.appending(path: "index.json")
            )
            try write(
                #"[["食べる","たべる","v1","v1",10,["to eat"],42,"common"]]"#,
                to: directory.appending(path: "term_bank_1.json")
            )
            try write(
                #"[["読む","よむ","v5m","v5",5,["to read"],43,""]]"#,
                to: directory.appending(path: "term_bank_2.json")
            )
            try write(
                #"[["common","frequency",1,"Common term",5]]"#,
                to: directory.appending(path: "tag_bank_1.json")
            )
            try write(
                #"[["の","freq",1]]"#,
                to: directory.appending(path: "term_meta_bank_1.json")
            )
            try write(
                #"[["亜","ア","つ.ぐ","jouyou",["Asia"],{"strokes":"7"}]]"#,
                to: directory.appending(path: "kanji_bank_1.json")
            )
            try write(
                #"[["亜","freq",1509]]"#,
                to: directory.appending(path: "kanji_meta_bank_1.json")
            )

            let preview = try parser.parse(
                source: DictionaryImportSource(url: directory)
            )

            #expect(preview.index.title == "Test Dictionary")
            #expect(preview.termBanks.map(\.fileName) == ["term_bank_1.json", "term_bank_2.json"])
            #expect(preview.totalEntries == 2)
            #expect(preview.totalTermMetadata == 1)
            #expect(preview.totalKanji == 1)
            #expect(preview.totalKanjiMetadata == 1)
            #expect(preview.totalTags == 1)
        }
    }

    @Test func rejectsDirectoryWithoutIndex() throws {
        try withTemporaryDirectory { directory in
            do {
                _ = try parser.parse(source: DictionaryImportSource(url: directory))
                Issue.record("Expected DictionaryImportError.missingIndex")
            } catch let DictionaryImportError.missingIndex(reportedDirectory) {
                #expect(reportedDirectory == directory)
            } catch {
                Issue.record("Expected DictionaryImportError.missingIndex, got \(error)")
            }
        }
    }

    @Test func parsesMetadataOnlyDictionary() throws {
        try withTemporaryDirectory { directory in
            try write(
                #"{"title":"Frequency","format":3,"revision":"1","frequencyMode":"rank-based"}"#,
                to: directory.appending(path: "index.json")
            )
            try write(
                #"[["の","freq",{"value":1,"displayValue":"1㋕"}]]"#,
                to: directory.appending(path: "term_meta_bank_1.json")
            )

            let preview = try parser.parse(
                source: DictionaryImportSource(url: directory)
            )

            #expect(preview.index.sequenced == nil)
            #expect(preview.totalEntries == 0)
            #expect(preview.totalTermMetadata == 1)
        }
    }

    @Test func rejectsDirectoryWithoutSupportedBanks() throws {
        try withTemporaryDirectory { directory in
            try write(
                #"{"title":"Test Dictionary","format":3,"revision":"1","sequenced":true}"#,
                to: directory.appending(path: "index.json")
            )

            do {
                _ = try parser.parse(source: DictionaryImportSource(url: directory))
                Issue.record("Expected DictionaryImportError.noSupportedBanks")
            } catch let DictionaryImportError.noSupportedBanks(reportedDirectory) {
                #expect(reportedDirectory == directory)
            } catch {
                Issue.record("Expected DictionaryImportError.noSupportedBanks, got \(error)")
            }
        }
    }

    @Test func rejectsUnsupportedDictionaryFormat() throws {
        try withTemporaryDirectory { directory in
            try write(
                #"{"title":"Legacy Dictionary","format":1,"revision":"1"}"#,
                to: directory.appending(path: "index.json")
            )
            try write(
                #"[]"#,
                to: directory.appending(path: "term_bank_1.json")
            )

            do {
                _ = try parser.parse(source: DictionaryImportSource(url: directory))
                Issue.record("Expected DictionaryImportError.unsupportedFormat")
            } catch DictionaryImportError.unsupportedFormat {
                // Expected.
            } catch {
                Issue.record("Expected DictionaryImportError.unsupportedFormat, got \(error)")
            }
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory
            .appending(path: "TsubameCoreTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        try body(directory)
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }
}
