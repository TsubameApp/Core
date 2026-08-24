import Foundation

enum TsubameABIV1Request: Equatable {
    case positioned(Positioned)
    case rangeScan(RangeScan)

    struct Positioned: Decodable, Equatable {
        let text: String
        let position: Int
        let resultLimit: Int
    }

    struct RangeScan: Decodable, Equatable {
        let text: String
        let range: Range
        let resultGroupLimit: Int
        let entriesPerGroupLimit: Int
    }

    struct Range: Codable, Equatable {
        let start: Int
        let end: Int
    }
}

enum TsubameABIV1RequestDecoder {
    private struct PositionedEnvelope: Decodable {
        let schemaVersion: UInt32
        let operation: String
        let request: TsubameABIV1Request.Positioned
    }

    private struct RangeScanEnvelope: Decodable {
        let schemaVersion: UInt32
        let operation: String
        let request: TsubameABIV1Request.RangeScan
    }

    static func decode(_ data: Data) throws -> TsubameABIV1Request {
        guard String(data: data, encoding: .utf8) != nil else {
            throw TsubameABIError.invalidUTF8(
                code: "invalid_request_utf8",
                message: "Request bytes are not valid UTF-8."
            )
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TsubameABIError.invalidJSON(
                code: "malformed_json",
                message: "Request is not valid JSON."
            )
        }

        guard let root = json as? [String: Any] else {
            throw invalidRequest("Request JSON must be an object.")
        }
        try validateKeys(
            in: root,
            allowed: ["schemaVersion", "operation", "request"],
            context: "request envelope"
        )
        guard let operation = root["operation"] as? String else {
            throw invalidRequest("Request operation must be a string.")
        }
        guard let request = root["request"] as? [String: Any] else {
            throw invalidRequest("Request payload must be an object.")
        }

        let decoder = JSONDecoder()
        do {
            switch operation {
            case "positionedLookup":
                try validateKeys(
                    in: request,
                    allowed: ["text", "position", "resultLimit"],
                    context: "positionedLookup request"
                )
                let envelope = try decoder.decode(PositionedEnvelope.self, from: data)
                try validateEnvelope(version: envelope.schemaVersion, operation: envelope.operation)
                return .positioned(envelope.request)

            case "rangeScan":
                try validateKeys(
                    in: request,
                    allowed: [
                        "text",
                        "range",
                        "resultGroupLimit",
                        "entriesPerGroupLimit",
                    ],
                    context: "rangeScan request"
                )
                guard let range = request["range"] as? [String: Any] else {
                    throw invalidRequest("rangeScan range must be an object.")
                }
                try validateKeys(
                    in: range,
                    allowed: ["start", "end"],
                    context: "rangeScan range"
                )
                let envelope = try decoder.decode(RangeScanEnvelope.self, from: data)
                try validateEnvelope(version: envelope.schemaVersion, operation: envelope.operation)
                return .rangeScan(envelope.request)

            default:
                throw TsubameABIError.unsupported(
                    code: "unsupported_operation",
                    message: "Request operation is unsupported."
                )
            }
        } catch let error as TsubameABIError {
            throw error
        } catch {
            throw invalidRequest("Request does not match the ABI v1 JSON schema.")
        }
    }

    private static func validateEnvelope(version: UInt32, operation: String) throws {
        guard version == TsubameABIConstants.payloadSchemaVersion else {
            throw TsubameABIError.unsupported(
                code: "unsupported_schema_version",
                message: "Request schema version is unsupported."
            )
        }
        guard operation == "positionedLookup" || operation == "rangeScan" else {
            throw TsubameABIError.unsupported(
                code: "unsupported_operation",
                message: "Request operation is unsupported."
            )
        }
    }

    private static func validateKeys(
        in object: [String: Any],
        allowed: Set<String>,
        context: String
    ) throws {
        let actual = Set(object.keys)
        let missing = allowed.subtracting(actual).sorted()
        guard missing.isEmpty else {
            throw invalidRequest("Missing field in \(context): \(missing[0]).")
        }
        let unknown = actual.subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw invalidRequest("Unknown field in \(context): \(unknown[0]).")
        }
    }

    private static func invalidRequest(_ message: String) -> TsubameABIError {
        .invalidRequest(code: "invalid_request", message: message)
    }
}

struct TsubameABIV1PositionedResponse: Encodable {
    let schemaVersion = TsubameABIConstants.payloadSchemaVersion
    let operation = "positionedLookup"
    let result: TsubameABILookupResultDTO
}

struct TsubameABIV1RangeScanResponse: Encodable {
    let schemaVersion = TsubameABIConstants.payloadSchemaVersion
    let operation = "rangeScan"
    let results: [TsubameABILookupResultDTO]
}

struct TsubameABILookupResultDTO: Encodable, Equatable {
    let sourceRange: TsubameABIV1Request.Range
    let entries: [TsubameABIDictionaryEntryDTO]

    init(_ result: LookupResult) throws {
        sourceRange = .init(start: result.sourceRange.start, end: result.sourceRange.end)
        entries = try result.entries.map(TsubameABIDictionaryEntryDTO.init)
    }
}

struct TsubameABIDictionaryEntryDTO: Encodable, Equatable {
    let id: Int64
    let expression: String
    let reading: String
    let definitionTags: String?
    let rules: String
    let score: Double
    let sequence: Int64
    let termTags: String
    let matches: [Match]
    let definitions: [Definition]

    struct Match: Encodable, Equatable {
        let key: String
        let keyType: String
    }

    struct Definition: Encodable, Equatable {
        let position: Int
        let kind: String
        let text: String?
        let content: TsubameABIJSONValue
    }

    init(_ entry: DictionaryEntry) throws {
        id = entry.id
        expression = entry.expression
        reading = entry.reading
        definitionTags = entry.definitionTags
        rules = entry.rules
        score = entry.score
        sequence = entry.sequence
        termTags = entry.termTags
        matches = entry.matches.map {
            Match(key: $0.key, keyType: $0.keyType.rawValue)
        }
        definitions = try entry.definitions.map { definition in
            let content: TsubameABIJSONValue
            do {
                content = try JSONDecoder().decode(
                    TsubameABIJSONValue.self,
                    from: definition.contentJSON
                )
            } catch {
                throw TsubameABIError.executionFailed(
                    code: "invalid_dictionary_content",
                    message: "Dictionary definition contains invalid JSON."
                )
            }
            return Definition(
                position: definition.position,
                kind: definition.kind,
                text: definition.text,
                content: content
            )
        }
    }
}

indirect enum TsubameABIJSONValue: Codable, Equatable {
    case null
    case boolean(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([TsubameABIJSONValue])
    case object([String: TsubameABIJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([TsubameABIJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: TsubameABIJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .boolean(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

struct TsubameABIErrorDTO: Encodable {
    let schemaVersion = TsubameABIConstants.payloadSchemaVersion
    let status: Int32
    let code: String
    let message: String
}
