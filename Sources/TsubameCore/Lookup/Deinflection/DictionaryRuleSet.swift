import Foundation

/// Canonical Yomitan dictionary rules accepted by Japanese deinflection.
public struct DictionaryRuleSet: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let ichidan = Self(rawValue: 1 << 0)
    public static let godan = Self(rawValue: 1 << 1)
    public static let kuru = Self(rawValue: 1 << 2)
    public static let suru = Self(rawValue: 1 << 3)
    public static let zuru = Self(rawValue: 1 << 4)
    public static let iAdjective = Self(rawValue: 1 << 5)

    static func parse(_ value: String) -> Self {
        var result: Self = []
        for token in value.split(whereSeparator: { $0.isWhitespace }) {
            if token.hasPrefix("v1") {
                result.insert(.ichidan)
            } else if token.hasPrefix("v5") {
                result.insert(.godan)
            } else if token == "vs" || token.hasPrefix("vs-") {
                result.insert(.suru)
            } else if token == "vk" {
                result.insert(.kuru)
            } else if token == "vz" {
                result.insert(.zuru)
            } else if token == "adj-i" || token.hasPrefix("adj-i") {
                result.insert(.iAdjective)
            }
        }
        return result
    }
}
