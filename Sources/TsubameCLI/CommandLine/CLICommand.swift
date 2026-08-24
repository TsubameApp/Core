import Foundation

enum CLICommand {
    case importDictionary(
        source: URL,
        dataRoot: URL?,
        debug: Bool,
        dryRun: Bool
    )
    case lookup(text: String, dataRoot: URL?, debug: Bool)
    case benchmarkLookup(
        text: String,
        dataRoot: URL?,
        warmupIterations: Int,
        measuredIterations: Int
    )

    static func parse(arguments: [String]) throws -> CLICommand {
        guard let command = arguments.first else {
            throw CLIError.invalidUsage
        }

        switch command {
        case "import":
            return try parseImport(arguments: Array(arguments.dropFirst()))
        case "lookup":
            return try parseLookup(arguments: Array(arguments.dropFirst()))
        case "bench":
            return try parseBenchmark(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.invalidUsage
        }
    }

    private static func parseImport(arguments: [String]) throws -> CLICommand {

        var source: URL?
        var dataRoot: URL?
        var debug = false
        var dryRun = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--debug":
                guard !debug else { throw CLIError.invalidUsage }
                debug = true
                index += 1
            case "--dry-run":
                guard !dryRun else { throw CLIError.invalidUsage }
                dryRun = true
                index += 1
            case "--data-root":
                guard dataRoot == nil,
                      index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError.invalidUsage
                }
                dataRoot = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
                index += 2
            default:
                guard source == nil, !arguments[index].hasPrefix("--") else {
                    throw CLIError.invalidUsage
                }
                source = URL(filePath: arguments[index])
                index += 1
            }
        }

        guard let source, !(dryRun && dataRoot != nil) else {
            throw CLIError.invalidUsage
        }
        return .importDictionary(
            source: source,
            dataRoot: dataRoot,
            debug: debug,
            dryRun: dryRun
        )
    }

    private static func parseLookup(arguments: [String]) throws -> CLICommand {
        var textComponents: [String] = []
        var dataRoot: URL?
        var debug = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--debug":
                guard !debug else { throw CLIError.invalidUsage }
                debug = true
                index += 1
            case "--data-root":
                guard dataRoot == nil,
                      index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError.invalidUsage
                }
                dataRoot = URL(
                    filePath: arguments[index + 1],
                    directoryHint: .isDirectory
                )
                index += 2
            default:
                guard !arguments[index].hasPrefix("--") else {
                    throw CLIError.invalidUsage
                }
                textComponents.append(arguments[index])
                index += 1
            }
        }

        let text = textComponents.joined(separator: " ")
        guard !text.isEmpty else {
            throw CLIError.invalidUsage
        }
        return .lookup(text: text, dataRoot: dataRoot, debug: debug)
    }

    private static func parseBenchmark(arguments: [String]) throws -> CLICommand {
        guard arguments.first == "lookup" else {
            throw CLIError.invalidUsage
        }

        var textComponents: [String] = []
        var dataRoot: URL?
        var warmupIterations = 20
        var measuredIterations = 1_000
        var hasWarmup = false
        var hasIterations = false
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--data-root":
                guard dataRoot == nil,
                      index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError.invalidUsage
                }
                dataRoot = URL(
                    filePath: arguments[index + 1],
                    directoryHint: .isDirectory
                )
                index += 2
            case "--warmup":
                guard !hasWarmup,
                      index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]),
                      (0...10_000).contains(value) else {
                    throw CLIError.invalidUsage
                }
                warmupIterations = value
                hasWarmup = true
                index += 2
            case "--iterations":
                guard !hasIterations,
                      index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]),
                      (1...100_000).contains(value) else {
                    throw CLIError.invalidUsage
                }
                measuredIterations = value
                hasIterations = true
                index += 2
            default:
                guard !arguments[index].hasPrefix("--") else {
                    throw CLIError.invalidUsage
                }
                textComponents.append(arguments[index])
                index += 1
            }
        }

        let text = textComponents.joined(separator: " ")
        guard !text.isEmpty else {
            throw CLIError.invalidUsage
        }
        return .benchmarkLookup(
            text: text,
            dataRoot: dataRoot,
            warmupIterations: warmupIterations,
            measuredIterations: measuredIterations
        )
    }

    func run() throws {
        switch self {
        case .importDictionary(let source, let dataRoot, let debug, let dryRun):
            try ImportDictionaryCommand.run(
                from: source,
                dataRootOverride: dataRoot,
                debug: debug,
                dryRun: dryRun
            )
        case .lookup(let text, let dataRoot, let debug):
            try LookupDictionaryCommand.run(
                text: text,
                dataRootOverride: dataRoot,
                debug: debug
            )
        case let .benchmarkLookup(text, dataRoot, warmup, iterations):
            try BenchmarkLookupCommand.run(
                text: text,
                dataRootOverride: dataRoot,
                warmupIterations: warmup,
                measuredIterations: iterations
            )
        }
    }
}
