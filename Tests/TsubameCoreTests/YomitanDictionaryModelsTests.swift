import Foundation
import Testing
@testable import TsubameCore

@Suite
struct YomitanDictionaryModelsTests {
    private var decoder: JSONDecoder { JSONDecoder() }

    @Test func decodesDictionaryIndex() throws {
        let data = Data(
            #"{"title":"Test Dictionary","format":3,"revision":"2026-08-24","sequenced":true}"#.utf8
        )

        let index = try decoder.decode(YomitanDictionaryIndex.self, from: data)

        #expect(index.title == "Test Dictionary")
        #expect(index.format == 3)
        #expect(index.revision == "2026-08-24")
        #expect(index.sequenced == true)
        #expect(index.author == nil)
    }

    @Test func decodesTermEntry() throws {
        let data = Data(
            #"["食べる","たべる","v1","v1",10,["to eat"],42,"common"]"#.utf8
        )

        let entry = try decoder.decode(YomitanTermEntry.self, from: data)

        #expect(entry.term == "食べる")
        #expect(entry.reading == "たべる")
        #expect(entry.definitionTags == "v1")
        #expect(entry.rules == "v1")
        #expect(entry.score == 10)
        #expect(entry.glossary == [.text("to eat")])
        #expect(entry.sequence == 42)
        #expect(entry.termTags == "common")
    }

    @Test func decodesIndexWithoutSequencedAndWithFrequencyMetadata() throws {
        let data = Data(
            #"{"title":"Frequency","format":3,"revision":"1","frequencyMode":"rank-based","author":"Test"}"#.utf8
        )

        let index = try decoder.decode(YomitanDictionaryIndex.self, from: data)

        #expect(index.sequenced == nil)
        #expect(index.frequencyMode == "rank-based")
        #expect(index.author == "Test")
    }

    @Test func decodesVersionAliasAndOfficialIndexMetadata() throws {
        let data = Data(
            #"{"title":"Test","revision":"1","version":3,"minimumYomitanVersion":"25.1.0","isUpdatable":true,"indexUrl":"https://example.com/index.json","downloadUrl":"https://example.com/dictionary.zip","sourceLanguage":"ja","targetLanguage":"en","tagMeta":{"common":{"category":"frequency","order":1.5,"score":2.5}}}"#.utf8
        )

        let index = try decoder.decode(YomitanDictionaryIndex.self, from: data)

        #expect(index.format == 3)
        #expect(index.version == 3)
        #expect(index.minimumYomitanVersion == "25.1.0")
        #expect(index.isUpdatable == true)
        #expect(index.indexURL == "https://example.com/index.json")
        #expect(index.downloadURL == "https://example.com/dictionary.zip")
        #expect(index.sourceLanguage == "ja")
        #expect(index.targetLanguage == "en")
        #expect(index.legacyTagMetadata?["common"]?.order == 1.5)
        #expect(index.legacyTagMetadata?["common"]?.score == 2.5)
    }

    @Test func decodesTextStructuredContentAndImageGlossary() throws {
        let data = Data(
            #"["食べる","たべる",null,"v1",10,["to eat",{"type":"structured-content","content":{"tag":"div","content":"definition"}},{"type":"image","path":"images/1.webp","collapsed":false}],42,"common"]"#.utf8
        )

        let entry = try decoder.decode(YomitanTermEntry.self, from: data)

        #expect(entry.definitionTags == nil)
        #expect(entry.glossary[0] == .text("to eat"))
        #expect(
            entry.glossary[1] == .object([
                "type": .string("structured-content"),
                "content": .object([
                    "tag": .string("div"),
                    "content": .string("definition")
                ])
            ])
        )
        #expect(
            entry.glossary[2] == .object([
                "type": .string("image"),
                "path": .string("images/1.webp"),
                "collapsed": .boolean(false)
            ])
        )
    }

    @Test func decodesFrequencyAndPitchMetadata() throws {
        let frequencyData = Data(
            #"["の","freq",{"value":1,"displayValue":"1㋕"}]"#.utf8
        )
        let pitchData = Data(
            #"["食べる","pitch",{"reading":"たべる","pitches":[{"position":2}]}]"#.utf8
        )

        let frequency = try decoder.decode(YomitanTermMetadata.self, from: frequencyData)
        let pitch = try decoder.decode(YomitanTermMetadata.self, from: pitchData)

        #expect(frequency.mode == "freq")
        #expect(
            frequency.data
                == .object(["value": .integer(1), "displayValue": .string("1㋕")])
        )
        #expect(pitch.mode == "pitch")
        #expect(
            pitch.data == .object([
                "reading": .string("たべる"),
                "pitches": .array([.object(["position": .integer(2)])])
            ])
        )
    }

    @Test func decodesObjectTextAndDeinflectionGlossary() throws {
        let data = Data(
            #"["食べた","たべた","","v1",0,[{"type":"text","text":"ate"},["食べる",["past"]]],1,""]"#.utf8
        )

        let entry = try decoder.decode(YomitanTermEntry.self, from: data)

        #expect(
            entry.glossary[0]
                == .object(["type": .string("text"), "text": .string("ate")])
        )
        #expect(
            entry.glossary[1]
                == .deinflection(term: "食べる", rules: ["past"])
        )
    }

    @Test func decodesIPAMetadata() throws {
        let data = Data(
            #"["食べる","ipa",{"reading":"たべる","transcriptions":[{"ipa":"tabeɾɯ","tags":["standard"]}]}]"#.utf8
        )

        let metadata = try decoder.decode(YomitanTermMetadata.self, from: data)

        #expect(metadata.mode == "ipa")
    }

    @Test func decodesKanjiEntry() throws {
        let data = Data(
            #"["亜","ア","つ.ぐ","jouyou",["Asia","come after"],{"grade":"8","strokes":"7"}]"#.utf8
        )

        let entry = try decoder.decode(YomitanKanjiEntry.self, from: data)

        #expect(entry.character == "亜")
        #expect(entry.onyomi == "ア")
        #expect(entry.kunyomi == "つ.ぐ")
        #expect(entry.tags == "jouyou")
        #expect(entry.meanings == ["Asia", "come after"])
        #expect(entry.stats == ["grade": "8", "strokes": "7"])
    }

    @Test func decodesKanjiMetadata() throws {
        let data = Data(
            ##"["亜","freq",{"value":1509,"displayValue":"#1509"}]"##.utf8
        )

        let metadata = try decoder.decode(YomitanKanjiMetadata.self, from: data)

        #expect(metadata.character == "亜")
        #expect(metadata.mode == "freq")
        #expect(
            metadata.data
                == .object(["value": .integer(1509), "displayValue": .string("#1509")])
        )
    }

    @Test func decodesDecimalTermAndTagScores() throws {
        let termData = Data(
            #"["語","ご","","",1.5,["word"],1,""]"#.utf8
        )
        let tagData = Data(
            #"["common","frequency",1.25,"Common term",2.5]"#.utf8
        )

        let term = try decoder.decode(YomitanTermEntry.self, from: termData)
        let tag = try decoder.decode(YomitanTag.self, from: tagData)

        #expect(term.score == 1.5)
        #expect(tag.order == 1.25)
        #expect(tag.score == 2.5)
    }

    @Test func decodesTag() throws {
        let data = Data(
            #"["common","frequency",1,"Common term",5]"#.utf8
        )

        let tag = try decoder.decode(YomitanTag.self, from: data)

        #expect(tag.name == "common")
        #expect(tag.category == "frequency")
        #expect(tag.order == 1)
        #expect(tag.notes == "Common term")
        #expect(tag.score == 5)
    }

    @Test func rejectsIncompleteTermEntry() {
        let data = Data(
            #"["食べる","たべる","v1"]"#.utf8
        )

        #expect(throws: DecodingError.self) {
            try decoder.decode(YomitanTermEntry.self, from: data)
        }
    }
}
