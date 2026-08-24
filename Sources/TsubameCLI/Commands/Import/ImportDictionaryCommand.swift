import Foundation
import TsubameCore
import TsubameCLIPlatform

enum ImportDictionaryCommand {
    static func run(
        from source: URL,
        dataRootOverride: URL?,
        debug: Bool,
        dryRun: Bool
    ) throws {
        let dryRunRoot: URL?
        let locations: TsubameStorageLocations
        if dryRun {
            let root = FileManager.default.temporaryDirectory.appending(
                path: "TsubameCLI-DryRun-\(UUID().uuidString.lowercased())",
                directoryHint: .isDirectory
            )
            dryRunRoot = root
            locations = TsubameStorageLocations(
                dataRoot: root.appending(path: "data", directoryHint: .isDirectory),
                cacheRoot: root.appending(path: "cache", directoryHint: .isDirectory),
                temporaryRoot: root.appending(path: "temporary", directoryHint: .isDirectory)
            )
        } else {
            let defaults = CLIStorageLocations.platformDefault()
            dryRunRoot = nil
            locations = TsubameStorageLocations(
                dataRoot: dataRootOverride ?? defaults.dataRoot,
                cacheRoot: defaults.cacheRoot,
                temporaryRoot: defaults.temporaryRoot
            )
        }
        defer {
            if let dryRunRoot {
                try? FileManager.default.removeItem(at: dryRunRoot)
            }
        }

        if dryRun {
            print("[import] Dry run: \(source.path)")
        } else {
            print("[import] Importing: \(source.path)")
            print("[import] Data root: \(locations.dataRoot.path)")
        }
        let result = try YomitanDictionaryInstaller(
            layout: DictionaryLibraryLayout(locations: locations)
        ).install(
            from: DictionaryImportSource(url: source),
            progress: progressHandler(debug: debug)
        )
        print("[import] Dictionary: \(result.manifest.title)")
        print("[import] Terms: \(result.manifest.termCount)")
        print("[import] Kanji: \(result.manifest.kanjiCount)")
        print(
            "[import] Resources: \(result.manifest.resourceCount) "
                + "(\(result.manifest.totalResourceBytes) bytes)"
        )
        if dryRun {
            print("[import] Dry run complete: the validated bundle was discarded.")
        } else {
            print("[import] Dictionary ID: \(result.dictionaryID.uuidString.lowercased())")
            print("[import] Bundle: \(result.bundleURL.path)")
        }
    }

    private static func progressHandler(
        debug: Bool
    ) -> DictionaryImportProgressHandler? {
        guard debug else { return nil }
        return { event in
            switch event {
            case .phaseStarted(let phase):
                print("[debug] \(phase.rawValue): started")
            case .phaseFinished(let phase, let elapsedSeconds):
                print("[debug] \(phase.rawValue): \(seconds(elapsedSeconds))")
            case .bankStarted(let kind, let fileName, let index, let total):
                print("[debug] bank \(index)/\(total) \(fileName) [\(kind.rawValue)]: started")
            case .bankFinished(
                let kind,
                let fileName,
                let index,
                let total,
                let entryCount,
                let elapsedSeconds
            ):
                print(
                    "[debug] bank \(index)/\(total) \(fileName) [\(kind.rawValue)]: "
                        + "\(entryCount) entries, \(seconds(elapsedSeconds))"
                )
            case .completed(let elapsedSeconds):
                print("[debug] total import: \(seconds(elapsedSeconds))")
            }
        }
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3fs", value)
    }
}
