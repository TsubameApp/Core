import Foundation
import TsubameCore

enum ImportPreviewCommand {
    static func run(from directory: URL) throws {
        let preview = try YomitanDictionaryParser().parse(
            source: DictionaryImportSource(url: directory)
        )

        print("[import] Opening: \(directory.path)")
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
        print("[import] Dry run only: no SQLite database was written.")
    }
}
