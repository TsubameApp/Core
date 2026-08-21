import Foundation
import TsubameCore

enum ImportPreviewCommand {
    static func run(from directory: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.sourceIsNotDirectory(directory)
        }

        let indexURL = directory.appending(path: "index.json")
        guard fileManager.fileExists(atPath: indexURL.path) else {
            throw CLIError.missingIndex(directory)
        }

        let decoder = JSONDecoder()
        let index = try decoder.decode(
            YomitanDictionaryIndex.self,
            from: Data(contentsOf: indexURL)
        )
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let termBanks = bankFiles(named: "term_bank_", in: files)

        guard !termBanks.isEmpty else {
            throw CLIError.noTermBanks(directory)
        }

        print("[import] Opening: \(directory.path)")
        print("[import] Dictionary: \(index.title) (format \(index.format), revision \(index.revision))")

        var totalEntries = 0
        for termBank in termBanks {
            let entries = try decoder.decode(
                [YomitanTermEntry].self,
                from: Data(contentsOf: termBank)
            )
            totalEntries += entries.count
            print("[import] \(termBank.lastPathComponent): \(entries.count) entries")
        }

        var totalTags = 0
        for tagBank in bankFiles(named: "tag_bank_", in: files) {
            let tags = try decoder.decode(
                [YomitanTag].self,
                from: Data(contentsOf: tagBank)
            )
            totalTags += tags.count
            print("[import] \(tagBank.lastPathComponent): \(tags.count) tags")
        }

        print("[import] Done. Parsed \(totalEntries) entries and \(totalTags) tags.")
        print("[import] Dry run only: no SQLite database was written.")
    }

    private static func bankFiles(named prefix: String, in files: [URL]) -> [URL] {
        files
            .filter {
                $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json"
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}
