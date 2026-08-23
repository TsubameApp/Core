import Foundation

enum CLICommand {
    case importPreview(source: URL)

    static func parse(arguments: [String]) throws -> CLICommand {
        guard arguments.first == "import", arguments.count == 2 else {
            throw CLIError.invalidUsage
        }

        return .importPreview(source: URL(filePath: arguments[1]))
    }

    func run() throws {
        switch self {
        case .importPreview(let source):
            try ImportPreviewCommand.run(from: source)
        }
    }
}
