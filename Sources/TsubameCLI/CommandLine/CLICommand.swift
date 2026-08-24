import Foundation

enum CLICommand {
    case importDictionary(
        source: URL,
        dataRoot: URL?,
        debug: Bool,
        dryRun: Bool
    )

    static func parse(arguments: [String]) throws -> CLICommand {
        guard arguments.first == "import" else {
            throw CLIError.invalidUsage
        }

        var source: URL?
        var dataRoot: URL?
        var debug = false
        var dryRun = false
        var index = 1

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

    func run() throws {
        switch self {
        case .importDictionary(let source, let dataRoot, let debug, let dryRun):
            try ImportDictionaryCommand.run(
                from: source,
                dataRootOverride: dataRoot,
                debug: debug,
                dryRun: dryRun
            )
        }
    }
}
