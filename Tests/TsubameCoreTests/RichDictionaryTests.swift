import Foundation
import Testing
@testable import TsubameCore

@Suite struct RichDictionaryTests {
    @Test func glossaryPreservesTextImagesAndUnknownChildren() throws {
        let data = Data(#"{"type":"structured-content","content":["bird",{"tag":"br"},{"tag":"custom","content":"fallback"},{"tag":"img","path":"images/bird.svg","width":120,"imageRendering":"auto","pixelated":true,"collapsed":true}]}"#.utf8)
        let nodes = try DictionaryGlossaryDecoder().decode(data)
        #expect(nodes.map(\.plainText).joined().contains("fallback"))
        let image = try #require(nodes.flatMap(\.images).first)
        #expect(image.path.rawValue == "images/bird.svg")
        #expect(image.width == 120)
        #expect(image.collapsed)
        #expect(!image.pixelated)
    }

    @Test func glossaryRejectsTraversalDimensionsAndExcessiveNesting() {
        for json in [
            #"{"type":"image","path":"../bird.png"}"#,
            #"{"type":"image","path":"https://example.org/image.png"}"#,
            #"{"type":"image","path":"bird.png","width":-1}"#,
            String(repeating: "[", count: 100) + "0" + String(repeating: "]", count: 100)
        ] {
            #expect(throws: (any Error).self) { try DictionaryGlossaryDecoder().decode(Data(json.utf8)) }
        }
    }

    @Test func parsesFrequencyVariantsAndFiltersReading() throws {
        for json in ["42", #"{"value":42,"displayValue":"42㋕"}"#, #"{"reading":"とり","frequency":{"value":42,"displayValue":"42㋕"}}"#] {
            let value = try #require(try DictionaryMetadataDecoder.frequency(Data(json.utf8), reading: "とり"))
            #expect(value.value == 42)
        }
        #expect(try DictionaryMetadataDecoder.frequency(Data(#"{"reading":"べつ","frequency":42}"#.utf8), reading: "とり") == nil)
    }

    @Test func pitchIncludesFollowingParticleAndHandlesMorae() throws {
        #expect(JapaneseMora.split("キャットー") == ["キャ", "ッ", "ト", "ー"])
        let data = Data(#"{"reading":"とり","pitches":[{"position":0},{"position":1},{"position":2},{"position":99}]}"#.utf8)
        let pitches = try DictionaryMetadataDecoder.pitches(data, reading: "とり")
        #expect(pitches.map(\.highPitch) == [[false, true, true], [true, false, false], [false, true, false]])
    }

    @Test func installedBundleProvidesLazyGlossaryMetadataAndSafeResources() throws {
        try withBundle { installed in
            let primary = try SQLiteDictionaryStore(databaseURL: installed.databaseURL, contentPolicy: .primary)
            let entry = try #require(primary.lookup(keys: ["鳥"], limit: 10).first)
            #expect(entry.definitions.allSatisfy { $0.contentJSON == Data("null".utf8) })
            let details = try primary.loadEntryDetails(entryID: entry.id)
            #expect(details.definitions.flatMap(\.nodes).flatMap(\.images).count == 1)
            #expect(details.metadata.termTags.map(\.name) == ["common"])
            #expect(details.metadata.frequencies.first?.value == 42)
            #expect(details.metadata.pitches.first?.position == 0)
            let resolver = try DictionaryResourceResolver(bundleURL: installed.bundleURL)
            let resource = try resolver.resolve(DictionaryResourcePath("images/bird.svg"))
            #expect(resource.mediaType == "image/svg+xml")
            #expect(throws: (any Error).self) { try resolver.resolve(DictionaryResourcePath("missing.svg")) }
            let imageURL = resource.fileURL
            try FileManager.default.removeItem(at: imageURL)
            try FileManager.default.createSymbolicLink(at: imageURL, withDestinationURL: installed.databaseURL)
            #expect(throws: (any Error).self) { try resolver.resolve(DictionaryResourcePath("images/bird.svg")) }
        }
    }

    @Test func importerRejectsMissingImageAndCleansStaging() throws {
        #expect(throws: (any Error).self) { try withBundle(imagePath: "images/missing.svg") { _ in } }
    }

    @Test func extremeTableSpansAreClampedWithoutIntegerOverflow() throws {
        let nodes = try DictionaryGlossaryDecoder().decode(Data(#"{"tag":"td","colSpan":1e100,"rowSpan":-1e100,"content":"cell"}"#.utf8))
        guard case .element(let element) = nodes.first else { Issue.record("Missing element"); return }
        #expect(element.columnSpan == 32)
        #expect(element.rowSpan == 1)
    }

    @Test func primaryLookupRetainsIdentityAndOmitsHeavyPayload() throws {
        try withBundle { installed in
            let primary = try SQLiteDictionaryStore(databaseURL: installed.databaseURL, contentPolicy: .primary)
            let complete = try SQLiteDictionaryStore(databaseURL: installed.databaseURL)
            let clock = ContinuousClock()
            let start = clock.now
            for _ in 0..<100 { _ = try primary.lookup(keys: ["鳥"], limit: 10) }
            let elapsed = start.duration(to: clock.now)
            let light = try primary.lookup(keys: ["鳥"], limit: 10)
            let full = try complete.lookup(keys: ["鳥"], limit: 10)
            #expect(light.map(\.id) == full.map(\.id))
            #expect(light.flatMap(\.definitions).compactMap(\.text) == full.flatMap(\.definitions).compactMap(\.text))
            let primaryBytes = light.flatMap(\.definitions).reduce(0) { $0 + $1.contentJSON.count }
            let completeBytes = full.flatMap(\.definitions).reduce(0) { $0 + $1.contentJSON.count }
            #expect(primaryBytes < completeBytes)
            print("P0 fixture: 100 primary lookups \(elapsed); glossary payload \(primaryBytes)/\(completeBytes) bytes (primary/complete)")
        }
    }

    private func withBundle(imagePath: String = "images/bird.svg", _ body: (InstalledDictionaryResult) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TsubameRichTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        try FileManager.default.createDirectory(at: source.appending(path: "images"), withIntermediateDirectories: true)
        try Data(#"{"title":"Rich fixture","format":3,"revision":"1"}"#.utf8).write(to: source.appending(path: "index.json"))
        let terms: [[Any]] = [["鳥", "とり", "common", "", 1, ["bird", ["type": "structured-content", "content": ["tag": "img", "path": imagePath]]], 1, "common"]]
        try JSONSerialization.data(withJSONObject: terms).write(to: source.appending(path: "term_bank_1.json"))
        try Data(#"[["鳥","freq",42],["鳥","pitch",{"reading":"とり","pitches":[{"position":0}]}]]"#.utf8).write(to: source.appending(path: "term_meta_bank_1.json"))
        try Data(#"[["common","frequency",1,"Common word",1]]"#.utf8).write(to: source.appending(path: "tag_bank_1.json"))
        try Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="red"/></svg>"#.utf8).write(to: source.appending(path: "images/bird.svg"))
        let layout = DictionaryLibraryLayout(locations: .init(dataRoot: root.appending(path: "data"), cacheRoot: root.appending(path: "cache"), temporaryRoot: root.appending(path: "tmp")))
        let installed = try YomitanDictionaryInstaller(layout: layout).install(from: .init(url: source))
        try body(installed)
    }
}
