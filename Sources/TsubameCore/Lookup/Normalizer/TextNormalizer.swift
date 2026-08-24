//
//  TextNormalizer.swift
//  TsubameCore
//
//  Created by k on 21.08.2026.
//

import Foundation

struct TextNormalizer: Sendable {
    func normalizedString(_ text: String) -> String {
        normalizeChunk(text)
    }

    func normalize(_ text: String) -> NormalizedText {
        var normalizedText = ""
        var mappings: [NormalizedText.Mapping] = []
        mappings.reserveCapacity(text.count)

        var originalUTF8Offset = 0
        var normalizedUTF8Offset = 0
        for character in text {
            let originalCharacter = String(character)
            // Compatibility mapping can leave kana marks decomposed on some
            // Foundation implementations, so compose canonically as well.
            let normalizedCharacter = normalizeChunk(originalCharacter)
            let originalEnd = originalUTF8Offset + originalCharacter.utf8.count
            let normalizedEnd = normalizedUTF8Offset + normalizedCharacter.utf8.count

            normalizedText.append(normalizedCharacter)
            mappings.append(
                NormalizedText.Mapping(
                    originalRange: UTF8TextRange(
                        start: originalUTF8Offset,
                        end: originalEnd
                    ),
                    normalizedRange: UTF8TextRange(
                        start: normalizedUTF8Offset,
                        end: normalizedEnd
                    )
                )
            )
            originalUTF8Offset = originalEnd
            normalizedUTF8Offset = normalizedEnd
        }

        return NormalizedText(
            text: normalizedText,
            originalUTF8Length: originalUTF8Offset,
            mappings: mappings
        )
    }

    private func normalizeChunk(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .precomposedStringWithCanonicalMapping
    }
}

struct NormalizedText: Sendable, Equatable {
    struct Mapping: Sendable, Equatable {
        let originalRange: UTF8TextRange
        let normalizedRange: UTF8TextRange
    }

    let text: String
    let originalUTF8Length: Int
    let mappings: [Mapping]

    var normalizedUTF8Length: Int {
        text.utf8.count
    }

    func normalizedUTF8Offset(forOriginalUTF8Offset offset: Int) throws -> Int {
        guard (0...originalUTF8Length).contains(offset) else {
            throw TextNormalizationMappingError.originalOffsetOutOfBounds(
                offset: offset,
                length: originalUTF8Length
            )
        }
        if offset == originalUTF8Length {
            return normalizedUTF8Length
        }
        guard let mapping = mapping(startingAtOriginalOffset: offset) else {
            throw TextNormalizationMappingError.originalOffsetIsNotCharacterBoundary(offset)
        }
        return mapping.normalizedRange.start
    }

    func normalizedUTF8Range(
        forOriginalUTF8Range range: UTF8TextRange
    ) throws -> UTF8TextRange {
        guard range.start >= 0,
              range.end >= range.start,
              range.end <= originalUTF8Length else {
            throw TextNormalizationMappingError.originalRangeOutOfBounds(
                range: range,
                length: originalUTF8Length
            )
        }
        return try UTF8TextRange(
            start: normalizedUTF8Offset(forOriginalUTF8Offset: range.start),
            end: normalizedUTF8Offset(forOriginalUTF8Offset: range.end)
        )
    }

    func originalUTF8Range(
        forNormalizedUTF8Range range: UTF8TextRange
    ) throws -> UTF8TextRange {
        let normalizedLength = normalizedUTF8Length
        guard range.start >= 0,
              range.end >= range.start,
              range.end <= normalizedLength else {
            throw TextNormalizationMappingError.normalizedRangeOutOfBounds(
                range: range,
                length: normalizedLength
            )
        }
        try validateNormalizedCharacterBoundary(range.start)
        try validateNormalizedCharacterBoundary(range.end)

        if range.start == range.end {
            let originalOffset = try originalUTF8Offset(
                forNormalizedBoundary: range.start
            )
            return UTF8TextRange(start: originalOffset, end: originalOffset)
        }

        guard let first = firstMapping(overlappingNormalizedOffset: range.start),
              let last = lastMapping(overlappingNormalizedEnd: range.end) else {
            throw TextNormalizationMappingError.normalizedRangeOutOfBounds(
                range: range,
                length: normalizedLength
            )
        }
        return UTF8TextRange(
            start: first.originalRange.start,
            end: last.originalRange.end
        )
    }

    private func originalUTF8Offset(forNormalizedBoundary offset: Int) throws -> Int {
        if offset == normalizedUTF8Length {
            return originalUTF8Length
        }
        guard let mapping = mapping(startingAtNormalizedOffset: offset) else {
            throw TextNormalizationMappingError.normalizedOffsetHasNoOriginalBoundary(offset)
        }
        return mapping.originalRange.start
    }

    private func validateNormalizedCharacterBoundary(_ offset: Int) throws {
        let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: offset)
        guard String.Index(utf8Index, within: text) != nil else {
            throw TextNormalizationMappingError.normalizedOffsetIsNotCharacterBoundary(offset)
        }
    }

    private func mapping(startingAtOriginalOffset offset: Int) -> Mapping? {
        var lowerBound = 0
        var upperBound = mappings.count
        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            if mappings[index].originalRange.start < offset {
                lowerBound = index + 1
            } else {
                upperBound = index
            }
        }
        guard lowerBound < mappings.count,
              mappings[lowerBound].originalRange.start == offset else {
            return nil
        }
        return mappings[lowerBound]
    }

    private func mapping(startingAtNormalizedOffset offset: Int) -> Mapping? {
        var lowerBound = 0
        var upperBound = mappings.count
        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            if mappings[index].normalizedRange.start < offset {
                lowerBound = index + 1
            } else {
                upperBound = index
            }
        }
        guard lowerBound < mappings.count,
              mappings[lowerBound].normalizedRange.start == offset else {
            return nil
        }
        return mappings[lowerBound]
    }

    private func firstMapping(overlappingNormalizedOffset offset: Int) -> Mapping? {
        var lowerBound = 0
        var upperBound = mappings.count
        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            if mappings[index].normalizedRange.end <= offset {
                lowerBound = index + 1
            } else {
                upperBound = index
            }
        }
        return lowerBound < mappings.count ? mappings[lowerBound] : nil
    }

    private func lastMapping(overlappingNormalizedEnd end: Int) -> Mapping? {
        var lowerBound = 0
        var upperBound = mappings.count
        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            if mappings[index].normalizedRange.start < end {
                lowerBound = index + 1
            } else {
                upperBound = index
            }
        }
        guard lowerBound > 0 else { return nil }
        return mappings[lowerBound - 1]
    }
}

enum TextNormalizationMappingError: Error, Sendable, Equatable {
    case originalOffsetOutOfBounds(offset: Int, length: Int)
    case originalOffsetIsNotCharacterBoundary(Int)
    case originalRangeOutOfBounds(range: UTF8TextRange, length: Int)
    case normalizedRangeOutOfBounds(range: UTF8TextRange, length: Int)
    case normalizedOffsetIsNotCharacterBoundary(Int)
    case normalizedOffsetHasNoOriginalBoundary(Int)
}
