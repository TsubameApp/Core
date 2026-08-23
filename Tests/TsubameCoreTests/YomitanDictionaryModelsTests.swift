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
        XCTAssertEqual(index.sequenced, true)
        XCTAssertNil(index.author)
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
        XCTAssertEqual(entry.glossary, [.text("to eat")])
        XCTAssertEqual(entry.sequence, 42)
        XCTAssertEqual(entry.termTags, "common")
    }

    func testDecodesIndexWithoutSequencedAndWithFrequencyMetadata() throws {
        let data = Data(
            #"{"title":"Frequency","format":3,"revision":"1","frequencyMode":"rank-based","author":"Test"}"#.utf8
        )

        let index = try decoder.decode(YomitanDictionaryIndex.self, from: data)

        XCTAssertNil(index.sequenced)
        XCTAssertEqual(index.frequencyMode, "rank-based")
        XCTAssertEqual(index.author, "Test")
    }

    func testDecodesVersionAliasAndOfficialIndexMetadata() throws {
        let data = Data(
            #"{"title":"Test","revision":"1","version":3,"minimumYomitanVersion":"25.1.0","isUpdatable":true,"indexUrl":"https://example.com/index.json","downloadUrl":"https://example.com/dictionary.zip","sourceLanguage":"ja","targetLanguage":"en","tagMeta":{"common":{"category":"frequency","order":1.5,"score":2.5}}}"#.utf8
        )

        let index = try decoder.decode(YomitanDictionaryIndex.self, from: data)

        XCTAssertEqual(index.format, 3)
        XCTAssertEqual(index.version, 3)
        XCTAssertEqual(index.minimumYomitanVersion, "25.1.0")
        XCTAssertEqual(index.isUpdatable, true)
        XCTAssertEqual(index.indexURL, "https://example.com/index.json")
        XCTAssertEqual(index.downloadURL, "https://example.com/dictionary.zip")
        XCTAssertEqual(index.sourceLanguage, "ja")
        XCTAssertEqual(index.targetLanguage, "en")
        XCTAssertEqual(index.legacyTagMetadata?["common"]?.order, 1.5)
        XCTAssertEqual(index.legacyTagMetadata?["common"]?.score, 2.5)
    }

    func testDecodesTextStructuredContentAndImageGlossary() throws {
        let data = Data(
            #"["食べる","たべる",null,"v1",10,["to eat",{"type":"structured-content","content":{"tag":"div","content":"definition"}},{"type":"image","path":"images/1.webp","collapsed":false}],42,"common"]"#.utf8
        )

        let entry = try decoder.decode(YomitanTermEntry.self, from: data)

        XCTAssertNil(entry.definitionTags)
        XCTAssertEqual(entry.glossary[0], .text("to eat"))
        XCTAssertEqual(
            entry.glossary[1],
            .object([
                "type": .string("structured-content"),
                "content": .object([
                    "tag": .string("div"),
                    "content": .string("definition")
                ])
            ])
        )
        XCTAssertEqual(
            entry.glossary[2],
            .object([
                "type": .string("image"),
                "path": .string("images/1.webp"),
                "collapsed": .boolean(false)
            ])
        )
    }

    func testDecodesFrequencyAndPitchMetadata() throws {
        let frequencyData = Data(
            #"["の","freq",{"value":1,"displayValue":"1㋕"}]"#.utf8
        )
        let pitchData = Data(
            #"["食べる","pitch",{"reading":"たべる","pitches":[{"position":2}]}]"#.utf8
        )

        let frequency = try decoder.decode(YomitanTermMetadata.self, from: frequencyData)
        let pitch = try decoder.decode(YomitanTermMetadata.self, from: pitchData)

        XCTAssertEqual(frequency.mode, "freq")
        XCTAssertEqual(
            frequency.data,
            .object(["value": .integer(1), "displayValue": .string("1㋕")])
        )
        XCTAssertEqual(pitch.mode, "pitch")
        XCTAssertEqual(
            pitch.data,
            .object([
                "reading": .string("たべる"),
                "pitches": .array([.object(["position": .integer(2)])])
            ])
        )
    }

    func testDecodesObjectTextAndDeinflectionGlossary() throws {
        let data = Data(
            #"["食べた","たべた","","v1",0,[{"type":"text","text":"ate"},["食べる",["past"]]],1,""]"#.utf8
        )

        let entry = try decoder.decode(YomitanTermEntry.self, from: data)

        XCTAssertEqual(
            entry.glossary[0],
            .object(["type": .string("text"), "text": .string("ate")])
        )
        XCTAssertEqual(
            entry.glossary[1],
            .deinflection(term: "食べる", rules: ["past"])
        )
    }

    func testDecodesIPAMetadata() throws {
        let data = Data(
            #"["食べる","ipa",{"reading":"たべる","transcriptions":[{"ipa":"tabeɾɯ","tags":["standard"]}]}]"#.utf8
        )

        let metadata = try decoder.decode(YomitanTermMetadata.self, from: data)

        XCTAssertEqual(metadata.mode, "ipa")
    }

    func testDecodesKanjiEntry() throws {
        let data = Data(
            #"["亜","ア","つ.ぐ","jouyou",["Asia","come after"],{"grade":"8","strokes":"7"}]"#.utf8
        )

        let entry = try decoder.decode(YomitanKanjiEntry.self, from: data)

        XCTAssertEqual(entry.character, "亜")
        XCTAssertEqual(entry.onyomi, "ア")
        XCTAssertEqual(entry.kunyomi, "つ.ぐ")
        XCTAssertEqual(entry.tags, "jouyou")
        XCTAssertEqual(entry.meanings, ["Asia", "come after"])
        XCTAssertEqual(entry.stats, ["grade": "8", "strokes": "7"])
    }

    func testDecodesKanjiMetadata() throws {
        let data = Data(
            ##"["亜","freq",{"value":1509,"displayValue":"#1509"}]"##.utf8
        )

        let metadata = try decoder.decode(YomitanKanjiMetadata.self, from: data)

        XCTAssertEqual(metadata.character, "亜")
        XCTAssertEqual(metadata.mode, "freq")
        XCTAssertEqual(
            metadata.data,
            .object(["value": .integer(1509), "displayValue": .string("#1509")])
        )
    }

    func testDecodesDecimalTermAndTagScores() throws {
        let termData = Data(
            #"["語","ご","","",1.5,["word"],1,""]"#.utf8
        )
        let tagData = Data(
            #"["common","frequency",1.25,"Common term",2.5]"#.utf8
        )

        let term = try decoder.decode(YomitanTermEntry.self, from: termData)
        let tag = try decoder.decode(YomitanTag.self, from: tagData)

        XCTAssertEqual(term.score, 1.5)
        XCTAssertEqual(tag.order, 1.25)
        XCTAssertEqual(tag.score, 2.5)
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
