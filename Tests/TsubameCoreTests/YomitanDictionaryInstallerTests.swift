import Foundation
import Testing
@testable import TsubameCore

@Suite
struct YomitanDictionaryInstallerTests {
    private let dictionaryID = UUID(uuidString: "630FCF9F-D0E8-497D-A19B-8E82CA00C2F5")!
    private let importID = UUID(uuidString: "8B822ECB-9B05-4336-9A31-BE61A6AEAE17")!
    private var fileManager: FileManager { .default }

    @Test func installsAllBanksManifestAndResourcesAsOneExactBundle() throws {
        try withTemporaryDirectory { root in
            let progress = ImportProgressRecorder()
            let layout = makeLayout(root: root)
            let archive = root.appending(path: "dictionary.zip")
            let svgBytes = Data(#"<svg xmlns="http://www.w3.org/2000/svg"><text>会</text></svg>"#.utf8)
            try makeZIP([
                .file(
                    "index.json",
                    #"{"title":"Bundle Test","format":3,"revision":"2026-08-24"}"#
                ),
                .file(
                    "term_bank_1.json",
                    #"[["鳥","とり","","",1,[{"type":"image","path":"images/bird.webp"},"bird"],1,""]]"#
                ),
                .file("term_meta_bank_1.json", #"[["鳥","freq",{"value":42}]]"#),
                .file("kanji_bank_1.json", #"[["鳥","チョウ","とり","jouyou",["bird"],{"strokes":"11"}]]"#),
                .file("kanji_meta_bank_1.json", #"[["鳥","freq",{"value":1000}]]"#),
                .file("tag_bank_1.json", #"[["jouyou","category",1,"Jōyō kanji",1]]"#),
                .file("styles.css", ".glossary { color: red; }"),
                .file("images/bird.webp", "synthetic webp bytes"),
                .file("images/icon.svg", #"<svg xmlns="http://www.w3.org/2000/svg"/>"#),
                .file("jitendex/会.svg", String(decoding: svgBytes, as: UTF8.self))
            ]).write(to: archive)

            let result = try YomitanDictionaryInstaller(layout: layout).install(
                from: DictionaryImportSource(url: archive),
                dictionaryID: dictionaryID,
                importID: importID,
                progress: progress.record
            )

            #expect(result.bundleURL == layout.dictionaryBundleURL(for: dictionaryID))
            #expect(result.databaseURL == layout.dictionaryDatabaseURL(for: dictionaryID))
            #expect(result.resourcesURL == layout.resourcesRootURL(for: dictionaryID))
            #expect(result.manifest.dictionaryID == dictionaryID)
            #expect(result.manifest.title == "Bundle Test")
            #expect(result.manifest.dictionarySchemaVersion == 2)
            #expect(result.manifest.termCount == 1)
            #expect(result.manifest.termMetadataCount == 1)
            #expect(result.manifest.kanjiCount == 1)
            #expect(result.manifest.kanjiMetadataCount == 1)
            #expect(result.manifest.tagCount == 1)
            #expect(result.manifest.definitionCount == 2)
            #expect(result.manifest.resourceCount == 4)
            #expect(result.manifest.totalResourceBytes > 0)

            #expect(fileManager.fileExists(atPath: result.databaseURL.path))
            #expect(fileManager.fileExists(atPath: layout.dictionaryManifestURL(for: dictionaryID).path))
            #expect(try String(
                contentsOf: result.resourcesURL.appending(path: "styles.css"),
                encoding: .utf8
            ) == ".glossary { color: red; }")
            #expect(try String(
                contentsOf: result.resourcesURL.appending(path: "images/bird.webp"),
                encoding: .utf8
            ) == "synthetic webp bytes")
            #expect(
                try Data(contentsOf: result.resourcesURL.appending(path: "jitendex/会.svg"))
                    == svgBytes
            )

            let installedFiles = try regularFilePaths(
                under: result.bundleURL,
                relativeTo: result.bundleURL
            )
            #expect(installedFiles == [
                "dictionary.sqlite",
                "manifest.json",
                "resources/images/bird.webp",
                "resources/images/icon.svg",
                "resources/jitendex/会.svg",
                "resources/styles.css"
            ])
            #expect(!fileManager.fileExists(
                atPath: layout.publicationStagingURL(for: importID).path
            ))
            #expect(!fileManager.fileExists(
                atPath: layout.temporaryWorkingURL(for: importID).path
            ))

            let decodedManifest = try JSONDecoder().decode(
                DictionaryBundleManifest.self,
                from: Data(contentsOf: layout.dictionaryManifestURL(for: dictionaryID))
            )
            #expect(decodedManifest == result.manifest)

            let connection = try SQLiteConnection(url: result.databaseURL, mode: .readOnly)
            defer { try? connection.close() }
            let resources = try connection.prepare(
                """
                SELECT logical_path, stored_relative_path, media_type, byte_size
                FROM resource ORDER BY logical_path
                """
            )
            #expect(try resources.step() == .row)
            #expect(resources.string(at: 0) == "images/bird.webp")
            #expect(resources.string(at: 1) == "resources/images/bird.webp")
            #expect(resources.string(at: 2) == "image/webp")
            #expect(resources.integer(at: 3) == 20)
            try resources.finalize()
            #expect(try rowCount("term_entry", connection: connection) == 1)
            #expect(try rowCount("term_metadata", connection: connection) == 1)
            #expect(try rowCount("kanji_entry", connection: connection) == 1)
            #expect(try rowCount("kanji_metadata", connection: connection) == 1)
            #expect(try rowCount("tag", connection: connection) == 1)
            #expect(try rowCount("resource", connection: connection) == 4)

            let events = progress.snapshot()
            #expect(events.contains { event in
                guard case .bankStarted(.term, "term_bank_1.json", 1, 5) = event else {
                    return false
                }
                return true
            })
            #expect(events.contains { event in
                guard case .bankFinished(
                    .term,
                    "term_bank_1.json",
                    1,
                    5,
                    1,
                    let elapsedSeconds
                ) = event else {
                    return false
                }
                return elapsedSeconds >= 0
            })
            for phase in [
                DictionaryImportPhase.sourcePreparation,
                .resourceCopy,
                .databaseSchema,
                .databaseTransaction,
                .databaseIndices,
                .databaseIntegrity,
                .manifest,
                .bundleValidation,
                .publication
            ] {
                #expect(events.contains(.phaseStarted(phase)))
                #expect(events.contains { event in
                    guard case .phaseFinished(phase, let elapsedSeconds) = event else {
                        return false
                    }
                    return elapsedSeconds >= 0
                })
            }
            #expect(events.contains { event in
                guard case .completed(let elapsedSeconds) = event else { return false }
                return elapsedSeconds >= 0
            })
        }
    }

    @Test func removesStagingWhenResourceIsUnsupported() throws {
        try withTemporaryDirectory { root in
            let layout = makeLayout(root: root)
            let archive = root.appending(path: "unsupported.zip")
            try makeZIP([
                .file(
                    "index.json",
                    #"{"title":"Broken Resources","format":3,"revision":"1"}"#
                ),
                .file("term_bank_1.json", #"[["鳥","とり","","",0,["bird"],1,""]]"#),
                .file("payload.exe", "not supported")
            ]).write(to: archive)

            #expect(throws: DictionaryInstallationError.self) {
                try YomitanDictionaryInstaller(layout: layout).install(
                    from: DictionaryImportSource(url: archive),
                    dictionaryID: dictionaryID,
                    importID: importID
                )
            }

            #expect(!fileManager.fileExists(
                atPath: layout.dictionaryBundleURL(for: dictionaryID).path
            ))
            #expect(!fileManager.fileExists(
                atPath: layout.publicationStagingURL(for: importID).path
            ))
            #expect(!fileManager.fileExists(
                atPath: layout.temporaryWorkingURL(for: importID).path
            ))
        }
    }

    @Test func refusesToReplaceExistingBundle() throws {
        try withTemporaryDirectory { root in
            let layout = makeLayout(root: root)
            let finalBundle = layout.dictionaryBundleURL(for: dictionaryID)
            try fileManager.createDirectory(at: finalBundle, withIntermediateDirectories: true)
            let marker = finalBundle.appending(path: "keep.txt")
            try Data("keep".utf8).write(to: marker)

            #expect(throws: DictionaryInstallationError.self) {
                try YomitanDictionaryInstaller(layout: layout).install(
                    from: DictionaryImportSource(url: root.appending(path: "missing.zip")),
                    dictionaryID: dictionaryID,
                    importID: importID
                )
            }
            #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
        }
    }

    private func makeLayout(root: URL) -> DictionaryLibraryLayout {
        DictionaryLibraryLayout(
            locations: TsubameStorageLocations(
                dataRoot: root.appending(path: "data", directoryHint: .isDirectory),
                cacheRoot: root.appending(path: "cache", directoryHint: .isDirectory),
                temporaryRoot: root.appending(path: "temporary", directoryHint: .isDirectory)
            )
        )
    }

    private func regularFilePaths(under root: URL, relativeTo base: URL) throws -> Set<String> {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try #require(
            fileManager.enumerator(at: root, includingPropertiesForKeys: keys)
        )
        var paths: Set<String> = []
        let basePath = base.standardizedFileURL.path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: Set(keys)).isRegularFile == true else {
                continue
            }
            let path = url.standardizedFileURL.path
            let relative = String(path.dropFirst(prefix.count))
            paths.insert(relative)
        }
        return paths
    }

    private func rowCount(_ table: String, connection: SQLiteConnection) throws -> Int64 {
        let statement = try connection.prepare("SELECT COUNT(*) FROM \(table)")
        defer { statement.finalizeIgnoringErrors() }
        #expect(try statement.step() == .row)
        return statement.integer(at: 0)
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory.appending(
            path: "TsubameInstallerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try body(directory)
    }
}

private final class ImportProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DictionaryImportProgressEvent] = []

    func record(_ event: DictionaryImportProgressEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [DictionaryImportProgressEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
