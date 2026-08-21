import Foundation

enum CLICommand {
    case importPreview(directory: URL)

    static func parse(arguments: [String]) throws -> CLICommand {
        guard arguments.first == "import", arguments.count == 2 else {
            throw CLIError.invalidUsage
        }

        return .importPreview(directory: URL(filePath: arguments[1]))
    }

    func run() throws {
        switch self {
        case .importPreview(let directory):
            try ImportPreviewCommand.run(from: directory)
        }
    }
}
