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
        let dictionaries = try installedDictionaries(layout: layout)
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

    private static func installedDictionaries(
        layout: DictionaryLibraryLayout,
        fileManager: FileManager = .default
    ) throws -> [InstalledDictionary] {
        let root = layout.dictionariesRootURL
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var dictionaries: [InstalledDictionary] = []
        for bundleURL in children {
            let values = try bundleURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  let directoryID = UUID(uuidString: bundleURL.lastPathComponent) else {
                continue
            }

            let manifestURL = bundleURL.appending(path: "manifest.json")
            let databaseURL = bundleURL.appending(path: "dictionary.sqlite")
            guard fileManager.fileExists(atPath: manifestURL.path),
                  fileManager.fileExists(atPath: databaseURL.path) else {
                throw LookupDictionaryCommandError.incompleteBundle(bundleURL)
            }

            let manifest: DictionaryBundleManifest
            do {
                manifest = try JSONDecoder().decode(
                    DictionaryBundleManifest.self,
                    from: Data(contentsOf: manifestURL)
                )
            } catch {
                throw LookupDictionaryCommandError.invalidManifest(
                    manifestURL,
                    reason: error.localizedDescription
                )
            }
            guard manifest.manifestVersion == DictionaryBundleManifest.currentVersion else {
                throw LookupDictionaryCommandError.unsupportedManifestVersion(
                    actual: manifest.manifestVersion,
                    expected: DictionaryBundleManifest.currentVersion,
                    manifestURL: manifestURL
                )
            }
            guard manifest.dictionaryID == directoryID else {
                throw LookupDictionaryCommandError.dictionaryIDMismatch(
                    directoryID: directoryID,
                    manifestID: manifest.dictionaryID,
                    bundleURL: bundleURL
                )
            }
            dictionaries.append(
                InstalledDictionary(manifest: manifest, databaseURL: databaseURL)
            )
        }

        return dictionaries.sorted {
            $0.manifest.dictionaryID.uuidString < $1.manifest.dictionaryID.uuidString
        }
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

private struct InstalledDictionary {
    let manifest: DictionaryBundleManifest
    let databaseURL: URL
}

private enum LookupDictionaryCommandError: LocalizedError {
    case incompleteBundle(URL)
    case invalidManifest(URL, reason: String)
    case unsupportedManifestVersion(actual: Int, expected: Int, manifestURL: URL)
    case dictionaryIDMismatch(directoryID: UUID, manifestID: UUID, bundleURL: URL)

    var errorDescription: String? {
        switch self {
        case .incompleteBundle(let url):
            "Dictionary bundle is incomplete: \(url.path)"
        case .invalidManifest(let url, let reason):
            "Dictionary manifest is invalid at \(url.path): \(reason)"
        case let .unsupportedManifestVersion(actual, expected, url):
            "Dictionary manifest version \(actual) is unsupported; expected \(expected): \(url.path)"
        case let .dictionaryIDMismatch(directoryID, manifestID, url):
            "Dictionary bundle ID \(directoryID) does not match manifest ID \(manifestID): \(url.path)"
        }
    }
}
