import Foundation

public enum DictionaryInstallationError: LocalizedError, Sendable, Equatable {
    case finalBundleAlreadyExists(URL)
    case finalBundleNotFound(URL)
    case stagingBundleAlreadyExists(URL)
    case replacementBackupAlreadyExists(URL)
    case invalidExistingManifest(URL)
    case replacementTitleMismatch(expected: String, actual: String)
    case replacementRecoveryFailed(URL)
    case invalidResourcePath(String)
    case unsupportedResource(String)
    case symbolicLinkResource(String)
    case resourceTooLarge(path: String, actual: Int64, maximum: Int64)
    case tooManyResources(actual: Int, maximum: Int)
    case resourcesTooLarge(actual: Int64, maximum: Int64)
    case resourceValidationFailed(String)
    case manifestValidationFailed

    public var errorDescription: String? {
        switch self {
        case .finalBundleAlreadyExists(let url):
            return "Dictionary bundle already exists: \(url.path)"
        case .finalBundleNotFound(let url):
            return "Dictionary bundle does not exist: \(url.path)"
        case .stagingBundleAlreadyExists(let url):
            return "Dictionary staging bundle already exists: \(url.path)"
        case .replacementBackupAlreadyExists(let url):
            return "Dictionary replacement backup already exists: \(url.path)"
        case .invalidExistingManifest(let url):
            return "Installed dictionary manifest is invalid: \(url.path)"
        case .replacementTitleMismatch(let expected, let actual):
            return "Replacement dictionary title \"\(actual)\" does not match \"\(expected)\"."
        case .replacementRecoveryFailed(let url):
            return "Could not restore the original dictionary bundle at \(url.path)."
        case .invalidResourcePath(let path):
            return "Dictionary contains an invalid resource path: \(path)"
        case .unsupportedResource(let path):
            return "Dictionary contains an unsupported resource: \(path)"
        case .symbolicLinkResource(let path):
            return "Dictionary resource is a symbolic link: \(path)"
        case .resourceTooLarge(let path, let actual, let maximum):
            return "Resource \(path) is \(actual) bytes; the limit is \(maximum)."
        case .tooManyResources(let actual, let maximum):
            return "Dictionary contains \(actual) resources; the limit is \(maximum)."
        case .resourcesTooLarge(let actual, let maximum):
            return "Dictionary resources total \(actual) bytes; the limit is \(maximum)."
        case .resourceValidationFailed(let path):
            return "Installed dictionary resource validation failed: \(path)"
        case .manifestValidationFailed:
            return "Installed dictionary manifest validation failed."
        }
    }
}

public struct DictionaryResourceImportLimits: Sendable, Equatable {
    public var maximumResourceCount: Int
    public var maximumResourceBytes: Int64
    public var maximumTotalResourceBytes: Int64

    public init(
        maximumResourceCount: Int = 100_000,
        maximumResourceBytes: Int64 = 512 * 1_024 * 1_024,
        maximumTotalResourceBytes: Int64 = 4 * 1_024 * 1_024 * 1_024
    ) {
        self.maximumResourceCount = maximumResourceCount
        self.maximumResourceBytes = maximumResourceBytes
        self.maximumTotalResourceBytes = maximumTotalResourceBytes
    }

    public static let `default` = DictionaryResourceImportLimits()
}
