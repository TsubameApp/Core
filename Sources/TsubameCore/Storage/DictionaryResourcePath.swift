import Foundation

/// A validated, platform-portable path relative to a dictionary's resource root.
public struct DictionaryResourcePath: Sendable, Hashable, Codable {
    public let rawValue: String
    public let components: [String]

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty else {
            throw DictionaryResourcePathError.empty
        }
        guard !rawValue.hasPrefix("/") && !Self.hasWindowsDrivePrefix(rawValue) else {
            throw DictionaryResourcePathError.absolute
        }
        guard !rawValue.contains("\\") else {
            throw DictionaryResourcePathError.backslashSeparator
        }
        guard !rawValue.contains(":") else {
            throw DictionaryResourcePathError.colon
        }
        guard !rawValue.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            throw DictionaryResourcePathError.controlCharacter
        }

        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DictionaryResourcePathError.invalidComponent
        }

        self.rawValue = rawValue
        self.components = components
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        do {
            try self.init(rawValue)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid dictionary resource path: \(error.localizedDescription)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func hasWindowsDrivePrefix(_ path: String) -> Bool {
        guard path.count >= 2 else {
            return false
        }

        let characters = Array(path.prefix(2))
        return characters[0].isASCII && characters[0].isLetter && characters[1] == ":"
    }
}

public enum DictionaryResourcePathError: LocalizedError, Sendable, Equatable {
    case empty
    case absolute
    case backslashSeparator
    case colon
    case controlCharacter
    case invalidComponent

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "The resource path is empty."
        case .absolute:
            return "Absolute resource paths are not allowed."
        case .backslashSeparator:
            return "Backslash path separators are not allowed."
        case .colon:
            return "Colons are not allowed in portable resource paths."
        case .controlCharacter:
            return "Control characters are not allowed in resource paths."
        case .invalidComponent:
            return "Empty, current-directory, and parent-directory path components are not allowed."
        }
    }
}
