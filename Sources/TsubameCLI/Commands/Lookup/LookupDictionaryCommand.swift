import Foundation
import TsubameCore
import TsubameCLIPlatform

enum LookupDictionaryCommand {
    private static let resultLimitPerDictionary = 100

    static func run(
        text: String,
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
        let request = try PositionedLookupRequest(
            text: text,
            position: 0,
            resultLimit: resultLimitPerDictionary
        )

        print("[lookup] Text: \(text)")
        print("[lookup] Data root: \(locations.dataRoot.path)")
        print("[lookup] Dictionaries: \(dictionaries.count)")

        guard !dictionaries.isEmpty else {
            print("[lookup] No imported dictionaries.")
            printElapsedTimeIfNeeded(
                label: "total",
                startedAt: totalStartedAt,
                debug: debug
            )
            return
        }

        var matchCount = 0
        var matchingDictionaryCount = 0
        for dictionary in dictionaries {
            let dictionaryStartedAt = ContinuousClock.now
            let store = try SQLiteDictionaryStore(databaseURL: dictionary.databaseURL)
            let result = try DictionaryLookup(store: store).lookup(request)
            let entries = result.entries
            if debug {
                print(
                    "[debug] dictionary "
                        + "\(dictionary.manifest.dictionaryID.uuidString.lowercased()): "
                        + "\(milliseconds(since: dictionaryStartedAt)), "
                        + "\(entries.count) entries, "
                        + "sourceRange=\(result.sourceRange.start)..<\(result.sourceRange.end)"
                )
            }
            guard !entries.isEmpty else { continue }

            matchingDictionaryCount += 1
            matchCount += entries.count
            print("")
            print("[\(dictionary.manifest.title)] \(dictionary.manifest.dictionaryID.uuidString.lowercased())")
            print("  [lookup] Surface: \(sourceText(in: text, range: result.sourceRange))")
            for entry in entries {
                printEntry(entry, debug: debug)
            }
        }

        print("")
        if matchCount == 0 {
            print("[lookup] No matches.")
        } else {
            print(
                "[lookup] Matches: \(matchCount) "
                    + "across \(matchingDictionaryCount) dictionaries."
            )
        }
        printElapsedTimeIfNeeded(
            label: "total",
            startedAt: totalStartedAt,
            debug: debug
        )
    }

    private static func printEntry(_ entry: DictionaryEntry, debug: Bool) {
        let headword: String
        if entry.reading.isEmpty || entry.reading == entry.expression {
            headword = entry.expression
        } else {
            headword = "\(entry.expression)【\(entry.reading)】"
        }
        print("  \(headword)")
        if debug {
            let matches = entry.matches.map {
                "\($0.keyType.rawValue):\($0.key)"
            }.joined(separator: ", ")
            print(
                "    [debug] score=\(entry.score) sequence=\(entry.sequence) "
                    + "rules=\(quoted(entry.rules)) "
                    + "definitionTags=\(quoted(entry.definitionTags ?? "")) "
                    + "termTags=\(quoted(entry.termTags)) matches=[\(matches)]"
            )
        }
        for definition in entry.definitions {
            let content = definition.text
                ?? String(decoding: definition.contentJSON, as: UTF8.self)
            print("    - \(content)")
        }
    }

    private static func sourceText(in text: String, range: UTF8TextRange) -> String {
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: range.start)
        let end = utf8.index(utf8.startIndex, offsetBy: range.end)
        return String(decoding: utf8[start..<end], as: UTF8.self)
    }

    private static func printElapsedTimeIfNeeded(
        label: String,
        startedAt: ContinuousClock.Instant,
        debug: Bool
    ) {
        guard debug else { return }
        print("[debug] \(label): \(milliseconds(since: startedAt))")
    }

    private static func milliseconds(since startedAt: ContinuousClock.Instant) -> String {
        let components = startedAt.duration(to: .now).components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f ms", milliseconds)
    }

    private static func quoted(_ value: String) -> String {
        String(reflecting: value)
    }
}
