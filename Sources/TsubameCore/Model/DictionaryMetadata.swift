import Foundation

public struct DictionaryTag: Sendable, Equatable {
    public let name: String
    public let category: String
    public let order: Double
    public let notes: String
    public let score: Double
}

public struct DictionaryFrequency: Sendable, Equatable {
    public let value: Double?
    public let displayValue: String
    public let reading: String?
}

public struct DictionaryPitchAccent: Sendable, Equatable {
    public let reading: String
    public let position: Int
    public let nasalPositions: [Int]
    public let devoicingPositions: [Int]
    public let tags: [String]

    public var morae: [String] { JapaneseMora.split(reading) }
    /// Includes the following particle, making heiban and odaka distinguishable.
    public var highPitch: [Bool] {
        (0...morae.count).map { index in
            position == 1 ? index == 0 : index > 0 && (position == 0 || index < position)
        }
    }
}

public enum JapaneseMora {
    public static func split(_ reading: String) -> [String] {
        let combining = Set("ゃゅょぁぃぅぇぉゎャュョァィゥェォヮ")
        var result: [String] = []
        for character in reading {
            if combining.contains(character), !result.isEmpty {
                result[result.count - 1].append(character)
            } else { result.append(String(character)) }
        }
        return result
    }
}

public struct DictionaryEntryMetadata: Sendable, Equatable {
    public let termTags: [DictionaryTag]
    public let definitionTags: [DictionaryTag]
    public let frequencies: [DictionaryFrequency]
    public let pitches: [DictionaryPitchAccent]
}

public struct DictionaryEntryDetails: Sendable, Equatable {
    public struct Definition: Sendable, Equatable {
        public let position: Int
        public let nodes: [GlossaryNode]
    }
    public let definitions: [Definition]
    public let metadata: DictionaryEntryMetadata
}

enum DictionaryMetadataDecoder {
    static func frequency(_ data: Data, reading: String) throws -> DictionaryFrequency? {
        let raw = try JSONDecoder().decode(YomitanJSONValue.self, from: data)
        let object = raw.objectValue
        let specifiedReading = object?["reading"]?.stringValue
        guard specifiedReading == nil || specifiedReading == reading else { return nil }
        let value = object?["frequency"] ?? raw
        let number = value.doubleValue ?? value.objectValue?["value"]?.doubleValue
        let display = value.objectValue?["displayValue"]?.stringValue ?? value.stringValue
            ?? number.map { $0.formatted(.number.grouping(.never)) }
        guard let display else { return nil }
        return DictionaryFrequency(value: number, displayValue: display, reading: specifiedReading)
    }

    static func pitches(_ data: Data, reading: String) throws -> [DictionaryPitchAccent] {
        let raw = try JSONDecoder().decode(YomitanJSONValue.self, from: data).objectValue ?? [:]
        guard let specifiedReading = raw["reading"]?.stringValue, specifiedReading == reading else { return [] }
        let count = JapaneseMora.split(reading).count
        guard count > 0, count <= 256 else { return [] }
        return (raw["pitches"]?.arrayValue ?? []).prefix(32).compactMap { value in
            guard let object = value.objectValue, let position = object["position"]?.doubleValue,
                  position >= 0, position <= Double(count), position.rounded() == position else { return nil }
            func positions(_ key: String) -> [Int] {
                (object[key]?.arrayValue ?? []).compactMap { value in
                    guard let number = value.doubleValue, number >= 1, number <= Double(count), number.rounded() == number else { return nil }
                    return Int(number)
                }
            }
            return DictionaryPitchAccent(reading: reading, position: Int(position),
                nasalPositions: positions("nasal"), devoicingPositions: positions("devoice"),
                tags: object["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        }
    }
}
