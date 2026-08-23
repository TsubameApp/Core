import Foundation
import TsubameCore

enum ImportPreviewCommand {
    static func run(from source: URL, databaseURL: URL? = nil) throws {
        if let databaseURL {
            try importDatabase(from: source, to: databaseURL)
            return
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let sourceExists = fileManager.fileExists(
            atPath: source.path,
            isDirectory: &isDirectory
        )

        let directory: URL
        var temporaryDirectory: URL?

        if sourceExists, isDirectory.boolValue {
            directory = source
        } else {
            let staging = fileManager.temporaryDirectory.appending(
                path: "TsubameCLI-\(UUID().uuidString.lowercased())",
                directoryHint: .isDirectory
            )
            print("[import] Extracting: \(source.path)")
            directory = try YomitanArchiveExtractor().extract(
                DictionaryImportSource(url: source),
                to: staging
            )
            temporaryDirectory = staging
        }
        defer {
            if let temporaryDirectory {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        let preview = try YomitanDictionaryParser().parse(
            source: DictionaryImportSource(url: directory)
        )

        print("[import] Opening: \(source.path)")
        printPreview(preview)
        print("[import] Dry run only: no SQLite database was written.")
    }

    private static func importDatabase(from source: URL, to databaseURL: URL) throws {
        print("[import] Importing: \(source.path)")
        let result = try YomitanSQLiteDictionaryImporter(
            temporaryRoot: FileManager.default.temporaryDirectory
        ).import(
            from: DictionaryImportSource(url: source),
            to: databaseURL
        )

        printPreview(result.preview)
        print("[import] Definitions: \(result.definitionCount)")
        print("[import] Lookup keys: \(result.lookupKeyCount)")
        print("[import] Database: \(result.databaseURL.path)")
    }

    private static func printPreview(_ preview: YomitanDictionaryPreview) {
        print("[import] Dictionary: \(preview.index.title) (format \(preview.index.format), revision \(preview.index.revision))")

        for termBank in preview.termBanks {
            print("[import] \(termBank.fileName): \(termBank.entryCount) entries")
        }

        for metadataBank in preview.termMetadataBanks {
            print("[import] \(metadataBank.fileName): \(metadataBank.entryCount) metadata entries")
        }

        for kanjiBank in preview.kanjiBanks {
            print("[import] \(kanjiBank.fileName): \(kanjiBank.entryCount) kanji entries")
        }

        for metadataBank in preview.kanjiMetadataBanks {
            print("[import] \(metadataBank.fileName): \(metadataBank.entryCount) kanji metadata entries")
        }

        for tagBank in preview.tagBanks {
            print("[import] \(tagBank.fileName): \(tagBank.entryCount) tags")
        }

        print(
            "[import] Done. Parsed \(preview.totalEntries) terms, "
                + "\(preview.totalTermMetadata) metadata entries, "
                + "\(preview.totalKanji) kanji, "
                + "\(preview.totalKanjiMetadata) kanji metadata entries and "
                + "\(preview.totalTags) tags."
        )
    }
}
