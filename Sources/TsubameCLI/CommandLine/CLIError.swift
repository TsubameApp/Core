import Foundation

enum CLIError: LocalizedError {
    case invalidUsage

    var errorDescription: String? {
        switch self {
        case .invalidUsage:
            return CLIHelp.usage
        }
    }
}
