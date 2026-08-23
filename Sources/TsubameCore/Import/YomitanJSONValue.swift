/// A lossless JSON value used at the Yomitan import boundary.
///
/// Structured glossary and metadata objects are intentionally preserved here
/// instead of being coupled to the application's eventual presentation model.
public indirect enum YomitanJSONValue: Decodable, Sendable, Equatable {
    case null
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([YomitanJSONValue])
    case object([String: YomitanJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([YomitanJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: YomitanJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }
}

/// One glossary value from a Yomitan term entry.
public enum YomitanGlossaryItem: Decodable, Sendable, Equatable {
    case text(String)
    case object([String: YomitanJSONValue])
    case deinflection(term: String, rules: [String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let object = try? container.decode([String: YomitanJSONValue].self) {
            self = .object(object)
        } else if var values = try? decoder.unkeyedContainer() {
            let term = try values.decode(String.self)
            let rules = try values.decode([String].self)
            guard values.isAtEnd else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "A Yomitan deinflection glossary item must have two values."
                )
            }
            self = .deinflection(term: term, rules: rules)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A Yomitan glossary item must be a string, object, or deinflection pair."
            )
        }
    }
}
