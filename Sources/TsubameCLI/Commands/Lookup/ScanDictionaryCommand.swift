import Foundation
import TsubameCore
import TsubameCLIPlatform

enum ScanDictionaryCommand {
    static func run(
        text: String,
        range: UTF8TextRange?,
        dataRootOverride: URL?,
        debug: Bool
    ) throws {
        let totalStartedAt = ContinuousClock.now
        let defaults = CLIStorageLocations.platformDefault()
        let locations = TsubameStorageLocations(
            dataRoot: dataRootOverride ?? defaults.dataRoot,
            cacheRoot: defaults.cacheRoot,
            temporaryRoot: defaults.temporaryRoot
        )
        let layout = DictionaryLibraryLayout(locations: locations)
        let dictionaries = try InstalledDictionaryLibrary.load(layout: layout)
        let scanRange = range ?? UTF8TextRange(start: 0, end: text.utf8.count)
        let request = try ScanLookupRequest(text: text, range: scanRange)

        print("[scan] Text: \(text)")
        print("[scan] Range: \(scanRange.start)..<\(scanRange.end)")
        print("[scan] Selection: \(CLIOutput.sourceText(in: text, range: scanRange))")
        print("[scan] Data root: \(locations.dataRoot.path)")
        print("[scan] Dictionaries: \(dictionaries.count)")

        guard !dictionaries.isEmpty else {
            print("[scan] No imported dictionaries.")
            CLIOutput.printElapsedTimeIfNeeded(
                label: "total",
                startedAt: totalStartedAt,
                debug: debug
            )
            return
        }

        var groupCount = 0
        var matchCount = 0
        var matchingDictionaryCount = 0
        for dictionary in dictionaries {
            let dictionaryStartedAt = ContinuousClock.now
            let store = try SQLiteDictionaryStore(databaseURL: dictionary.databaseURL)
            let results = try DictionaryLookup(store: store).scan(request)
            let dictionaryEntryCount = results.reduce(0) { $0 + $1.entries.count }
            if debug {
                print(
                    "[debug] dictionary "
                        + "\(dictionary.manifest.dictionaryID.uuidString.lowercased()): "
                        + "\(CLIOutput.formattedMilliseconds(since: dictionaryStartedAt)), "
                        + "\(results.count) groups, "
                        + "\(dictionaryEntryCount) entries"
                )
            }
            guard !results.isEmpty else { continue }

            matchingDictionaryCount += 1
            groupCount += results.count
            matchCount += dictionaryEntryCount
            print("")
            print("[\(dictionary.manifest.title)] \(dictionary.manifest.dictionaryID.uuidString.lowercased())")
            for result in results {
                print("  [scan] Surface: \(CLIOutput.sourceText(in: text, range: result.sourceRange))")
                print("  [scan] Source range: \(result.sourceRange.start)..<\(result.sourceRange.end)")
                for entry in result.entries {
                    CLIOutput.printEntry(entry, debug: debug, indentation: "    ")
                }
            }
        }

        print("")
        if matchCount == 0 {
            print("[scan] No matches.")
        } else {
            print(
                "[scan] Groups: \(groupCount), matches: \(matchCount) "
                    + "across \(matchingDictionaryCount) dictionaries."
            )
        }
        CLIOutput.printElapsedTimeIfNeeded(
            label: "total",
            startedAt: totalStartedAt,
            debug: debug
        )
    }
}
