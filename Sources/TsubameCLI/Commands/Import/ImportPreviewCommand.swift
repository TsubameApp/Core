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

        for tagBank in preview.tagBanks {
            print("[import] \(tagBank.fileName): \(tagBank.entryCount) tags")
        }

        print("[import] Done. Parsed \(preview.totalEntries) entries and \(preview.totalTags) tags.")
        print("[import] Dry run only: no SQLite database was written.")
    }
}
