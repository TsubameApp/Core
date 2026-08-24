import Foundation

public enum DictionaryLookupKeyType: String, Sendable, Equatable {
    case expression
    case reading
}

public struct DictionaryEntryMatch: Sendable, Equatable {
    public let key: String
    public let keyType: DictionaryLookupKeyType

    public init(key: String, keyType: DictionaryLookupKeyType) {
        self.key = key
        self.keyType = keyType
    }
}

public struct DictionaryDefinition: Sendable, Equatable {
    public let position: Int
    public let kind: String
    public let text: String?
    public let contentJSON: Data

    public init(
        position: Int,
        kind: String,
        text: String?,
        contentJSON: Data
    ) {
        self.position = position
        self.kind = kind
        self.text = text
        self.contentJSON = contentJSON
    }
}

public struct DictionaryEntry: Sendable, Equatable {
    public let id: Int64
    public let expression: String
    public let reading: String
    public let definitionTags: String?
    public let rules: String
    public let score: Double
    public let sequence: Int64
    public let termTags: String
    public let matches: [DictionaryEntryMatch]
    public let definitions: [DictionaryDefinition]

    public init(
        id: Int64,
        expression: String,
        reading: String,
        definitionTags: String?,
        rules: String,
        score: Double,
        sequence: Int64,
        termTags: String,
        matches: [DictionaryEntryMatch],
        definitions: [DictionaryDefinition]
    ) {
        self.id = id
        self.expression = expression
        self.reading = reading
        self.definitionTags = definitionTags
        self.rules = rules
        self.score = score
        self.sequence = sequence
        self.termTags = termTags
        self.matches = matches
        self.definitions = definitions
    }
}
