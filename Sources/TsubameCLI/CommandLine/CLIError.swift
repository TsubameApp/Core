import Foundation

enum CLIError: LocalizedError {
    case invalidUsage
    case sourceIsNotDirectory(URL)
    case missingIndex(URL)
    case noTermBanks(URL)

    var errorDescription: String? {
        switch self {
        case .invalidUsage:
            return CLIHelp.usage
        case .sourceIsNotDirectory(let source):
            return "Dictionary source is not a directory: \(source.path)"
        case .missingIndex(let directory):
            return "index.json was not found in \(directory.path)"
        case .noTermBanks(let directory):
            return "No term_bank_*.json files were found in \(directory.path)"
        }
    }
}
