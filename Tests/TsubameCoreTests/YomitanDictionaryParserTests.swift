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

            let preview = try parser.parse(
                source: DictionaryImportSource(url: directory)
            )

            XCTAssertEqual(preview.index.title, "Test Dictionary")
            XCTAssertEqual(preview.termBanks.map(\.fileName), ["term_bank_1.json", "term_bank_2.json"])
            XCTAssertEqual(preview.totalEntries, 2)
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

    func testRejectsDirectoryWithoutTermBanks() throws {
        try withTemporaryDirectory { directory in
            try write(
                #"{"title":"Test Dictionary","format":3,"revision":"1","sequenced":true}"#,
                to: directory.appending(path: "index.json")
            )

            XCTAssertThrowsError(
                try parser.parse(source: DictionaryImportSource(url: directory))
            ) { error in
                guard let importError = error as? DictionaryImportError,
                      case .noTermBanks(let reportedDirectory) = importError else {
                    return XCTFail("Expected DictionaryImportError.noTermBanks, got \(error)")
                }

                XCTAssertEqual(reportedDirectory, directory)
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
