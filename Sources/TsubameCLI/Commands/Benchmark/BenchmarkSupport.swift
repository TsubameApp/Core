import Foundation

struct BenchmarkStatistics {
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

enum BenchmarkOutput {
    static func printWarmed(operation: String, statistics: BenchmarkStatistics) {
        print(
            "  [bench] Warmed \(operation): "
                + "p50=\(CLIOutput.formatted(milliseconds: statistics.p50)) "
                + "p95=\(CLIOutput.formatted(milliseconds: statistics.p95)) "
                + "p99=\(CLIOutput.formatted(milliseconds: statistics.p99)) "
                + "min=\(CLIOutput.formatted(milliseconds: statistics.minimum)) "
                + "max=\(CLIOutput.formatted(milliseconds: statistics.maximum))"
        )
    }
}
