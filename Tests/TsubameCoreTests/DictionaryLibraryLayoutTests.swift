import Foundation
import XCTest
@testable import TsubameCore

final class DictionaryLibraryLayoutTests: XCTestCase {
    private let dictionaryID = UUID(uuidString: "A6A53A94-665A-43E4-877D-6F9BCE107D01")!
    private let importID = UUID(uuidString: "44F9BEE7-2A44-4EA3-8095-D05B84B06738")!

    func testBuildsDurableLayoutFromInjectedDataRoot() {
        let layout = makeLayout()
        let dictionaryComponent = dictionaryID.uuidString.lowercased()
        let importComponent = importID.uuidString.lowercased()

        XCTAssertEqual(
            layout.applicationDatabaseURL,
            layout.locations.dataRoot.appending(path: "application.sqlite")
        )
        XCTAssertEqual(
            layout.dictionariesRootURL,
            layout.locations.dataRoot.appending(path: "Dictionaries", directoryHint: .isDirectory)
        )
        XCTAssertEqual(
            layout.publicationStagingURL(for: importID),
            layout.publicationStagingRootURL.appending(path: importComponent, directoryHint: .isDirectory)
        )
        XCTAssertEqual(
            layout.dictionaryDatabaseURL(for: dictionaryID),
            layout.dictionariesRootURL
                .appending(path: dictionaryComponent, directoryHint: .isDirectory)
                .appending(path: "dictionary.sqlite")
        )
        XCTAssertEqual(
            layout.dictionaryManifestURL(for: dictionaryID),
            layout.dictionariesRootURL
                .appending(path: dictionaryComponent, directoryHint: .isDirectory)
                .appending(path: "manifest.json")
        )
    }

    func testKeepsTemporaryWorkOutsideDurablePublicationStaging() {
        let layout = makeLayout()

        XCTAssertEqual(
            layout.temporaryWorkingURL(for: importID),
            layout.locations.temporaryRoot
                .appending(path: "Tsubame", directoryHint: .isDirectory)
                .appending(path: importID.uuidString.lowercased(), directoryHint: .isDirectory)
        )
        XCTAssertTrue(
            layout.publicationStagingURL(for: importID).path.hasPrefix(layout.locations.dataRoot.path)
        )
        XCTAssertFalse(
            layout.publicationStagingURL(for: importID).path.hasPrefix(layout.locations.temporaryRoot.path)
        )
    }

    func testResolvesValidResourcePathsInsideDictionaryBundle() throws {
        let layout = makeLayout()
        let image = try DictionaryResourcePath("images/0005.png")
        let nestedSVG = try DictionaryResourcePath("jitendex/noun.svg")
        let resourcesRoot = layout.resourcesRootURL(for: dictionaryID)

        XCTAssertEqual(
            layout.resourceURL(for: image, dictionaryID: dictionaryID),
            resourcesRoot.appending(path: "images").appending(path: "0005.png")
        )
        XCTAssertEqual(
            layout.resourceURL(for: nestedSVG, dictionaryID: dictionaryID),
            resourcesRoot.appending(path: "jitendex").appending(path: "noun.svg")
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
        let root = FileManager.default.temporaryDirectory.appending(
            path: "TsubameLayoutTests",
            directoryHint: .isDirectory
        )

        return DictionaryLibraryLayout(
            locations: TsubameStorageLocations(
                dataRoot: root.appending(path: "data", directoryHint: .isDirectory),
                cacheRoot: root.appending(path: "cache", directoryHint: .isDirectory),
                temporaryRoot: root.appending(path: "temporary", directoryHint: .isDirectory)
            )
        )
    }
}
