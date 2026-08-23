import Foundation

enum CLICommand {
    case importPreview(source: URL)
    case importDatabase(source: URL, database: URL)

    static func parse(arguments: [String]) throws -> CLICommand {
        guard arguments.first == "import" else {
            throw CLIError.invalidUsage
        }

        if arguments.count == 2 {
            return .importPreview(source: URL(filePath: arguments[1]))
        }
        if arguments.count == 4, arguments[2] == "--database" {
            return .importDatabase(
                source: URL(filePath: arguments[1]),
                database: URL(filePath: arguments[3])
            )
        }
        throw CLIError.invalidUsage
    }

    func run() throws {
        switch self {
        case .importPreview(let source):
            try ImportPreviewCommand.run(from: source)
        case .importDatabase(let source, let database):
            try ImportPreviewCommand.run(from: source, databaseURL: database)
        }
    }
}
