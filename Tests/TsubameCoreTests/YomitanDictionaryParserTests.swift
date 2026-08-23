import Foundation
import XCTest
@testable import TsubameCore

final class YomitanDictionaryParserTests: XCTestCase {
    private let parser = YomitanDictionaryParser()
    private let fileManager = FileManager.default

    func testParsesDictionaryDirectory() throws {
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

            XCTAssertEqual(preview.index.title, "Test Dictionary")
            XCTAssertEqual(preview.termBanks.map(\.fileName), ["term_bank_1.json", "term_bank_2.json"])
            XCTAssertEqual(preview.totalEntries, 2)
            XCTAssertEqual(preview.totalTermMetadata, 1)
            XCTAssertEqual(preview.totalKanji, 1)
            XCTAssertEqual(preview.totalKanjiMetadata, 1)
            XCTAssertEqual(preview.totalTags, 1)
        }
    }

    func testRejectsDirectoryWithoutIndex() throws {
        try withTemporaryDirectory { directory in
            XCTAssertThrowsError(
                try parser.parse(source: DictionaryImportSource(url: directory))
            ) { error in
                guard let importError = error as? DictionaryImportError,
                      case .missingIndex(let reportedDirectory) = importError else {
                    return XCTFail("Expected DictionaryImportError.missingIndex, got \(error)")
                }

                XCTAssertEqual(reportedDirectory, directory)
            }
        }
    }

    func testParsesMetadataOnlyDictionary() throws {
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

            XCTAssertNil(preview.index.sequenced)
            XCTAssertEqual(preview.totalEntries, 0)
            XCTAssertEqual(preview.totalTermMetadata, 1)
        }
    }

    func testRejectsDirectoryWithoutSupportedBanks() throws {
        try withTemporaryDirectory { directory in
            try write(
                #"{"title":"Test Dictionary","format":3,"revision":"1","sequenced":true}"#,
                to: directory.appending(path: "index.json")
            )

            XCTAssertThrowsError(
                try parser.parse(source: DictionaryImportSource(url: directory))
            ) { error in
                guard let importError = error as? DictionaryImportError,
                      case .noSupportedBanks(let reportedDirectory) = importError else {
                    return XCTFail("Expected DictionaryImportError.noSupportedBanks, got \(error)")
                }

                XCTAssertEqual(reportedDirectory, directory)
            }
        }
    }

    func testRejectsUnsupportedDictionaryFormat() throws {
        try withTemporaryDirectory { directory in
            try write(
                #"{"title":"Legacy Dictionary","format":1,"revision":"1"}"#,
                to: directory.appending(path: "index.json")
            )
            try write(
                #"[]"#,
                to: directory.appending(path: "term_bank_1.json")
            )

            XCTAssertThrowsError(
                try parser.parse(source: DictionaryImportSource(url: directory))
            ) { error in
                guard let importError = error as? DictionaryImportError,
                      case .unsupportedFormat = importError else {
                    return XCTFail("Expected DictionaryImportError.unsupportedFormat, got \(error)")
                }
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
