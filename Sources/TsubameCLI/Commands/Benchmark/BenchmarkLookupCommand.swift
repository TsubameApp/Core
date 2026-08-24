import Foundation
import TsubameCore
import TsubameCLIPlatform

enum BenchmarkLookupCommand {
    private struct Statistics {
        let minimum: Double
        let p50: Double
        let p95: Double
        let p99: Double
        let maximum: Double

        init(samples: [Double]) {
            let sorted = samples.sorted()
            minimum = sorted[0]
            p50 = Self.percentile(0.50, in: sorted)
            p95 = Self.percentile(0.95, in: sorted)
            p99 = Self.percentile(0.99, in: sorted)
            maximum = sorted[sorted.count - 1]
        }

        private static func percentile(_ percentile: Double, in sorted: [Double]) -> Double {
            let rank = Int(ceil(percentile * Double(sorted.count))) - 1
            return sorted[max(0, min(rank, sorted.count - 1))]
        }
    }

    static func run(
        text: String,
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
        let request = try PositionedLookupRequest(text: text, position: 0)

        print("[bench] Text: \(text)")
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
            let storeMilliseconds = milliseconds(since: storeStartedAt)
            let lookup = DictionaryLookup(store: store)

            let firstStartedAt = ContinuousClock.now
            let firstResult = try lookup.lookup(request)
            let firstMilliseconds = milliseconds(since: firstStartedAt)
            checksum &+= resultChecksum(firstResult)

            for _ in 0..<warmupIterations {
                checksum &+= resultChecksum(try lookup.lookup(request))
            }

            var samples: [Double] = []
            samples.reserveCapacity(measuredIterations)
            for _ in 0..<measuredIterations {
                let startedAt = ContinuousClock.now
                let result = try lookup.lookup(request)
                samples.append(milliseconds(since: startedAt))
                checksum &+= resultChecksum(result)
            }
            let statistics = Statistics(samples: samples)

            print("")
            print("[\(dictionary.manifest.title)] \(dictionary.manifest.dictionaryID.uuidString.lowercased())")
            print("  [bench] Store open: \(formatted(storeMilliseconds))")
            let firstSuffix = dictionaryIndex == 0
                ? " (includes process-wide rule initialization)"
                : ""
            print("  [bench] First lookup: \(formatted(firstMilliseconds))\(firstSuffix)")
            print(
                "  [bench] Warmed lookup: "
                    + "p50=\(formatted(statistics.p50)) "
                    + "p95=\(formatted(statistics.p95)) "
                    + "p99=\(formatted(statistics.p99)) "
                    + "min=\(formatted(statistics.minimum)) "
                    + "max=\(formatted(statistics.maximum))"
            )
            print(
                "  [bench] First result: \(firstResult.entries.count) entries, "
                    + "sourceRange=\(firstResult.sourceRange.start)..<\(firstResult.sourceRange.end)"
            )
        }

        print("")
        print("[bench] Checksum: \(checksum)")
    }

    private static func resultChecksum(_ result: LookupResult) -> Int {
        result.entries.count &+ result.sourceRange.start &+ result.sourceRange.end
    }

    private static func milliseconds(since startedAt: ContinuousClock.Instant) -> Double {
        let components = startedAt.duration(to: .now).components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func formatted(_ milliseconds: Double) -> String {
        String(format: "%.3f ms", milliseconds)
    }
}
