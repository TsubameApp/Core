import Foundation
import XCTest
@testable import TsubameCore

final class DictionaryLibraryLayoutTests: XCTestCase {
    private let dictionaryID = UUID(uuidString: "A6A53A94-665A-43E4-877D-6F9BCE107D01")!
    private let importID = UUID(uuidString: "44F9BEE7-2A44-4EA3-8095-D05B84B06738")!

    func testBuildsDurableLayoutFromInjectedDataRoot() {
        let layout = makeLayout()

        XCTAssertEqual(layout.applicationDatabaseURL.path, "/test/data/application.sqlite")
        XCTAssertEqual(layout.dictionariesRootURL.path, "/test/data/Dictionaries")
        XCTAssertEqual(layout.publicationStagingRootURL.path, "/test/data/Dictionaries/.staging")
        XCTAssertEqual(
            layout.publicationStagingURL(for: importID).path,
            "/test/data/Dictionaries/.staging/44f9bee7-2a44-4ea3-8095-d05b84b06738"
        )
        XCTAssertEqual(
            layout.dictionaryDatabaseURL(for: dictionaryID).path,
            "/test/data/Dictionaries/a6a53a94-665a-43e4-877d-6f9bce107d01/dictionary.sqlite"
        )
        XCTAssertEqual(
            layout.dictionaryManifestURL(for: dictionaryID).path,
            "/test/data/Dictionaries/a6a53a94-665a-43e4-877d-6f9bce107d01/manifest.json"
        )
    }

    func testKeepsTemporaryWorkOutsideDurablePublicationStaging() {
        let layout = makeLayout()

        XCTAssertEqual(
            layout.temporaryWorkingURL(for: importID).path,
            "/test/tmp/Tsubame/44f9bee7-2a44-4ea3-8095-d05b84b06738"
        )
        XCTAssertTrue(layout.publicationStagingURL(for: importID).path.hasPrefix("/test/data/"))
        XCTAssertFalse(layout.publicationStagingURL(for: importID).path.hasPrefix("/test/tmp/"))
    }

    func testResolvesValidResourcePathsInsideDictionaryBundle() throws {
        let layout = makeLayout()
        let image = try DictionaryResourcePath("images/0005.png")
        let nestedSVG = try DictionaryResourcePath("jitendex/noun.svg")

        XCTAssertEqual(
            layout.resourceURL(for: image, dictionaryID: dictionaryID).path,
            "/test/data/Dictionaries/a6a53a94-665a-43e4-877d-6f9bce107d01/resources/images/0005.png"
        )
        XCTAssertEqual(
            layout.resourceURL(for: nestedSVG, dictionaryID: dictionaryID).path,
            "/test/data/Dictionaries/a6a53a94-665a-43e4-877d-6f9bce107d01/resources/jitendex/noun.svg"
        )
    }

    func testRejectsUnsafeOrNonPortableResourcePaths() {
        let invalidPaths = [
            "",
            "/images/a.png",
            "../secret.txt",
            "images/../../a.png",
            "images/./a.png",
            "images//a.png",
            "images/",
            #"C:\Users\x\a.png"#,
            "C:/Users/x/a.png",
            #"\\server\share\a.png"#,
            #"images\a.png"#,
            "images/a:stream.png",
            "images/\u{0}a.png"
        ]

        for path in invalidPaths {
            XCTAssertThrowsError(try DictionaryResourcePath(path), "Expected rejection for \(path.debugDescription)")
        }
    }

    func testCodableRoundTripPreservesValidatedPath() throws {
        let path = try DictionaryResourcePath("images/reference.webp")

        let encoded = try JSONEncoder().encode(path)
        let decoded = try JSONDecoder().decode(DictionaryResourcePath.self, from: encoded)

        XCTAssertEqual(decoded, path)
    }

    private func makeLayout() -> DictionaryLibraryLayout {
        DictionaryLibraryLayout(
            locations: TsubameStorageLocations(
                dataRoot: URL(filePath: "/test/data", directoryHint: .isDirectory),
                cacheRoot: URL(filePath: "/test/cache", directoryHint: .isDirectory),
                temporaryRoot: URL(filePath: "/test/tmp", directoryHint: .isDirectory)
            )
        )
    }
}
