/// Metadata stored in a Yomitan dictionary's `index.json`.
public struct YomitanDictionaryIndex: Decodable, Sendable, Equatable {
    public let title: String
    /// Effective dictionary format, decoded from `format` or its `version` alias.
    public let format: Int
    public let revision: String
    public let version: Int?
    public let minimumYomitanVersion: String?
    public let sequenced: Bool?
    public let author: String?
    public let isUpdatable: Bool?
    public let indexURL: String?
    public let downloadURL: String?
    public let url: String?
    public let description: String?
    public let attribution: String?
    public let sourceLanguage: String?
    public let targetLanguage: String?
    public let frequencyMode: String?
    public let legacyTagMetadata: [String: YomitanLegacyTagMetadata]?

    private enum CodingKeys: String, CodingKey {
        case title
        case format
        case revision
        case version
        case minimumYomitanVersion
        case sequenced
        case author
        case isUpdatable
        case indexURL = "indexUrl"
        case downloadURL = "downloadUrl"
        case url
        case description
        case attribution
        case sourceLanguage
        case targetLanguage
        case frequencyMode
        case legacyTagMetadata = "tagMeta"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        title = try values.decode(String.self, forKey: .title)
        revision = try values.decode(String.self, forKey: .revision)
        version = try values.decodeIfPresent(Int.self, forKey: .version)

        if let declaredFormat = try values.decodeIfPresent(Int.self, forKey: .format) {
            format = declaredFormat
        } else if let version {
            format = version
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.format,
                DecodingError.Context(
                    codingPath: values.codingPath,
                    debugDescription: "Yomitan index requires either format or version."
                )
            )
        }

        minimumYomitanVersion = try values.decodeIfPresent(String.self, forKey: .minimumYomitanVersion)
        sequenced = try values.decodeIfPresent(Bool.self, forKey: .sequenced)
        author = try values.decodeIfPresent(String.self, forKey: .author)
        isUpdatable = try values.decodeIfPresent(Bool.self, forKey: .isUpdatable)
        indexURL = try values.decodeIfPresent(String.self, forKey: .indexURL)
        downloadURL = try values.decodeIfPresent(String.self, forKey: .downloadURL)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        attribution = try values.decodeIfPresent(String.self, forKey: .attribution)
        sourceLanguage = try values.decodeIfPresent(String.self, forKey: .sourceLanguage)
        targetLanguage = try values.decodeIfPresent(String.self, forKey: .targetLanguage)
        frequencyMode = try values.decodeIfPresent(String.self, forKey: .frequencyMode)
        legacyTagMetadata = try values.decodeIfPresent(
            [String: YomitanLegacyTagMetadata].self,
            forKey: .legacyTagMetadata
        )
    }
}

/// Obsolete inline tag metadata which may still appear in `index.json`.
public struct YomitanLegacyTagMetadata: Decodable, Sendable, Equatable {
    public let category: String?
    public let order: Double?
    public let notes: String?
    public let score: Double?
}

/// One row from a Yomitan `term_bank_*.json` file.
///
/// Yomitan represents a term as a positional JSON array rather than an object:
/// `[term, reading, definitionTags, rules, score, glossary, sequence, termTags]`.
public struct YomitanTermEntry: Decodable, Sendable, Equatable {
    public let term: String
    public let reading: String
    public let definitionTags: String?
    public let rules: String
    public let score: Double
    public let glossary: [YomitanGlossaryItem]
    public let sequence: Int
    public let termTags: String

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()

        term = try values.decode(String.self)
        reading = try values.decode(String.self)
        definitionTags = try values.decodeIfPresent(String.self)
        rules = try values.decode(String.self)
        score = try values.decode(Double.self)
        glossary = try values.decode([YomitanGlossaryItem].self)
        sequence = try values.decode(Int.self)
        termTags = try values.decode(String.self)
    }
}

/// One row from a Yomitan `term_meta_bank_*.json` file.
///
/// Its positional JSON schema is `[term, mode, data]`. The downloaded corpus
/// uses `freq` and `pitch` modes with several different shapes for `data`, so
/// the value is preserved losslessly for transformation by a later layer.
public struct YomitanTermMetadata: Decodable, Sendable, Equatable {
    public let term: String
    public let mode: String
    public let data: YomitanJSONValue

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()

        term = try values.decode(String.self)
        mode = try values.decode(String.self)
        data = try values.decode(YomitanJSONValue.self)
    }
}

/// One row from a Yomitan `kanji_bank_*.json` file.
///
/// Its positional JSON schema is
/// `[character, onyomi, kunyomi, tags, meanings, stats]`.
public struct YomitanKanjiEntry: Decodable, Sendable, Equatable {
    public let character: String
    public let onyomi: String
    public let kunyomi: String
    public let tags: String
    public let meanings: [String]
    public let stats: [String: String]

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()

        character = try values.decode(String.self)
        onyomi = try values.decode(String.self)
        kunyomi = try values.decode(String.self)
        tags = try values.decode(String.self)
        meanings = try values.decode([String].self)
        stats = try values.decode([String: String].self)
    }
}

/// One row from a Yomitan `kanji_meta_bank_*.json` file.
///
/// Its positional JSON schema is `[character, mode, data]` where the official
/// v3 schema currently defines `freq` metadata.
public struct YomitanKanjiMetadata: Decodable, Sendable, Equatable {
    public let character: String
    public let mode: String
    public let data: YomitanJSONValue

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()

        character = try values.decode(String.self)
        mode = try values.decode(String.self)
        data = try values.decode(YomitanJSONValue.self)
    }
}

/// One row from a Yomitan `tag_bank_*.json` file.
///
/// Its positional JSON schema is `[name, category, order, notes, score]`.
public struct YomitanTag: Decodable, Sendable, Equatable {
    public let name: String
    public let category: String
    public let order: Double
    public let notes: String
    public let score: Double

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()

        name = try values.decode(String.self)
        category = try values.decode(String.self)
        order = try values.decode(Double.self)
        notes = try values.decode(String.self)
        score = try values.decode(Double.self)
    }
}
