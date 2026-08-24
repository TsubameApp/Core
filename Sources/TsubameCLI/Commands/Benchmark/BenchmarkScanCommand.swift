import Foundation
import TsubameCore
import TsubameCLIPlatform

enum BenchmarkScanCommand {
    static func run(
        text: String,
        range: UTF8TextRange?,
        dataRootOverride: URL?,
        warmupIterations: Int,
        measuredIterations: Int
    ) throws {
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

        print("[bench] Operation: scan")
        print("[bench] Text: \(text)")
        print("[bench] Range: \(scanRange.start)..<\(scanRange.end)")
        print("[bench] Data root: \(locations.dataRoot.path)")
        print("[bench] Dictionaries: \(dictionaries.count)")
        print("[bench] Warmup iterations: \(warmupIterations)")
        print("[bench] Measured iterations: \(measuredIterations)")
#if DEBUG
        print("[bench] Warning: this is a debug build; use swift build -c release for performance measurements.")
#endif

        guard !dictionaries.isEmpty else {
            print("[bench] No imported dictionaries.")
            return
        }

        var checksum = 0
        for (dictionaryIndex, dictionary) in dictionaries.enumerated() {
            let storeStartedAt = ContinuousClock.now
            let store = try SQLiteDictionaryStore(databaseURL: dictionary.databaseURL)
            let storeMilliseconds = CLIOutput.milliseconds(since: storeStartedAt)
            let lookup = DictionaryLookup(store: store)

            let firstStartedAt = ContinuousClock.now
            let firstResults = try lookup.scan(request)
            let firstMilliseconds = CLIOutput.milliseconds(since: firstStartedAt)
            checksum &+= resultsChecksum(firstResults)

            for _ in 0..<warmupIterations {
                checksum &+= resultsChecksum(try lookup.scan(request))
            }

            var samples: [Double] = []
            samples.reserveCapacity(measuredIterations)
            for _ in 0..<measuredIterations {
                let startedAt = ContinuousClock.now
                let results = try lookup.scan(request)
                samples.append(CLIOutput.milliseconds(since: startedAt))
                checksum &+= resultsChecksum(results)
            }
            let statistics = BenchmarkStatistics(samples: samples)
            let firstEntryCount = firstResults.reduce(0) { $0 + $1.entries.count }

            print("")
            print("[\(dictionary.manifest.title)] \(dictionary.manifest.dictionaryID.uuidString.lowercased())")
            print("  [bench] Store open: \(CLIOutput.formatted(milliseconds: storeMilliseconds))")
            let firstSuffix = dictionaryIndex == 0
                ? " (includes process-wide rule initialization)"
                : ""
            print("  [bench] First scan: \(CLIOutput.formatted(milliseconds: firstMilliseconds))\(firstSuffix)")
            BenchmarkOutput.printWarmed(operation: "scan", statistics: statistics)
            print(
                "  [bench] First result: \(firstResults.count) groups, "
                    + "\(firstEntryCount) entries"
            )
        }

        print("")
        print("[bench] Checksum: \(checksum)")
    }

    private static func resultsChecksum(_ results: [LookupResult]) -> Int {
        results.reduce(0) { checksum, result in
            checksum
                &+ result.entries.count
                &+ result.sourceRange.start
                &+ result.sourceRange.end
        }
    }
}
