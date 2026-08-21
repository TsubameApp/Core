/// Metadata stored in a Yomitan dictionary's `index.json`.
public struct YomitanDictionaryIndex: Decodable, Sendable, Equatable {
    public let title: String
    public let format: Int
    public let revision: String
    public let sequenced: Bool
}

/// One row from a Yomitan `term_bank_*.json` file.
///
/// Yomitan represents a term as a positional JSON array rather than an object:
/// `[term, reading, definitionTags, rules, score, glossary, sequence, termTags]`.
public struct YomitanTermEntry: Decodable, Sendable, Equatable {
    public let term: String
    public let reading: String
    public let definitionTags: String
    public let rules: String
    public let score: Int
    public let glossary: [String]
    public let sequence: Int
    public let termTags: String

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()

        term = try values.decode(String.self)
        reading = try values.decode(String.self)
        definitionTags = try values.decode(String.self)
        rules = try values.decode(String.self)
        score = try values.decode(Int.self)
        glossary = try values.decode([String].self)
        sequence = try values.decode(Int.self)
        termTags = try values.decode(String.self)
    }
}

/// One row from a Yomitan `tag_bank_*.json` file.
///
/// Its positional JSON schema is `[name, category, order, notes, score]`.
public struct YomitanTag: Decodable, Sendable, Equatable {
    public let name: String
    public let category: String
    public let order: Int
    public let notes: String
    public let score: Int

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()

        name = try values.decode(String.self)
        category = try values.decode(String.self)
        order = try values.decode(Int.self)
        notes = try values.decode(String.self)
        score = try values.decode(Int.self)
    }
}
