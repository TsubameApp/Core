import Foundation
import XCTest
@testable import TsubameCore

final class YomitanDictionaryModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodesDictionaryIndex() throws {
        let data = Data(
            #"{"title":"Test Dictionary","format":3,"revision":"2026-08-24","sequenced":true}"#.utf8
        )

        let index = try decoder.decode(YomitanDictionaryIndex.self, from: data)

        XCTAssertEqual(index.title, "Test Dictionary")
        XCTAssertEqual(index.format, 3)
        XCTAssertEqual(index.revision, "2026-08-24")
        XCTAssertTrue(index.sequenced)
    }

    func testDecodesTermEntry() throws {
        let data = Data(
            #"["食べる","たべる","v1","v1",10,["to eat"],42,"common"]"#.utf8
        )

        let entry = try decoder.decode(YomitanTermEntry.self, from: data)

        XCTAssertEqual(entry.term, "食べる")
        XCTAssertEqual(entry.reading, "たべる")
        XCTAssertEqual(entry.definitionTags, "v1")
        XCTAssertEqual(entry.rules, "v1")
        XCTAssertEqual(entry.score, 10)
        XCTAssertEqual(entry.glossary, ["to eat"])
        XCTAssertEqual(entry.sequence, 42)
        XCTAssertEqual(entry.termTags, "common")
    }

    func testDecodesTag() throws {
        let data = Data(
            #"["common","frequency",1,"Common term",5]"#.utf8
        )

        let tag = try decoder.decode(YomitanTag.self, from: data)

        XCTAssertEqual(tag.name, "common")
        XCTAssertEqual(tag.category, "frequency")
        XCTAssertEqual(tag.order, 1)
        XCTAssertEqual(tag.notes, "Common term")
        XCTAssertEqual(tag.score, 5)
    }

    func testRejectsIncompleteTermEntry() {
        let data = Data(
            #"["食べる","たべる","v1"]"#.utf8
        )

        XCTAssertThrowsError(
            try decoder.decode(YomitanTermEntry.self, from: data)
        )
    }
}
