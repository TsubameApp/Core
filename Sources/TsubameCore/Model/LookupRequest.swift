//
//  LookupRequest.swift
//  TsubameCore
//
//  Created by k on 21.08.2026.
//

import Foundation

/// A half-open byte range in the UTF-8 representation of a string.
public struct UTF8TextRange: Sendable, Equatable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public enum LookupRequestLimits {
    public static let maximumTextUTF8Length = 65_536
    public static let maximumScanRangeUTF8Length = 16_384
    public static let maximumResultGroups = 256
    public static let maximumEntriesPerGroup = 500
}

public enum LookupRequestError: LocalizedError, Sendable, Equatable {
    case emptyText
    case textTooLong(actual: Int, maximum: Int)
    case positionOutOfBounds(position: Int, textUTF8Length: Int)
    case rangeOutOfBounds(range: UTF8TextRange, textUTF8Length: Int)
    case offsetIsNotCharacterBoundary(Int)
    case emptyScanRange
    case scanRangeTooLong(actual: Int, maximum: Int)
    case invalidResultLimit(Int)
    case resultLimitTooLarge(actual: Int, maximum: Int)
    case invalidResultGroupLimit(Int)
    case resultGroupLimitTooLarge(actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            "Lookup text must not be empty."
        case let .textTooLong(actual, maximum):
            "Lookup text is \(actual) UTF-8 bytes; maximum is \(maximum)."
        case let .positionOutOfBounds(position, textUTF8Length):
            "Lookup position \(position) is outside 0...\(textUTF8Length)."
        case let .rangeOutOfBounds(range, textUTF8Length):
            "Lookup range \(range.start)..<\(range.end) is outside 0...\(textUTF8Length)."
        case let .offsetIsNotCharacterBoundary(offset):
            "UTF-8 offset \(offset) is not a character boundary."
        case .emptyScanRange:
            "Scan range must not be empty."
        case let .scanRangeTooLong(actual, maximum):
            "Scan range is \(actual) UTF-8 bytes; maximum is \(maximum)."
        case let .invalidResultLimit(limit):
            "Result limit must be positive; received \(limit)."
        case let .resultLimitTooLarge(actual, maximum):
            "Result limit \(actual) exceeds maximum \(maximum)."
        case let .invalidResultGroupLimit(limit):
            "Result group limit must be positive; received \(limit)."
        case let .resultGroupLimitTooLarge(actual, maximum):
            "Result group limit \(actual) exceeds maximum \(maximum)."
        }
    }
}

public struct PositionedLookupRequest: Sendable, Equatable {
    public let text: String
    /// A UTF-8 byte offset on a `Character` boundary in `text`.
    public let position: Int
    public let resultLimit: Int

    public init(
        text: String,
        position: Int,
        resultLimit: Int = 100
    ) throws {
        let textUTF8Length = try validateText(text)
        guard (0...textUTF8Length).contains(position) else {
            throw LookupRequestError.positionOutOfBounds(
                position: position,
                textUTF8Length: textUTF8Length
            )
        }
        try validateCharacterBoundary(position, in: text)
        try validateResultLimit(resultLimit)

        self.text = text
        self.position = position
        self.resultLimit = resultLimit
    }
}

public struct ScanLookupRequest: Sendable, Equatable {
    public let text: String
    public let range: UTF8TextRange
    public let resultGroupLimit: Int
    public let entriesPerGroupLimit: Int

    public init(
        text: String,
        range: UTF8TextRange,
        resultGroupLimit: Int = 100,
        entriesPerGroupLimit: Int = 100
    ) throws {
        let textUTF8Length = try validateText(text)
        guard range.start >= 0,
              range.end >= range.start,
              range.end <= textUTF8Length
        else {
            throw LookupRequestError.rangeOutOfBounds(
                range: range,
                textUTF8Length: textUTF8Length
            )
        }
        guard range.start != range.end else {
            throw LookupRequestError.emptyScanRange
        }
        try validateCharacterBoundary(range.start, in: text)
        try validateCharacterBoundary(range.end, in: text)
        let rangeLength = range.end - range.start
        guard rangeLength <= LookupRequestLimits.maximumScanRangeUTF8Length else {
            throw LookupRequestError.scanRangeTooLong(
                actual: rangeLength,
                maximum: LookupRequestLimits.maximumScanRangeUTF8Length
            )
        }
        try validateResultGroupLimit(resultGroupLimit)
        try validateResultLimit(entriesPerGroupLimit)

        self.text = text
        self.range = range
        self.resultGroupLimit = resultGroupLimit
        self.entriesPerGroupLimit = entriesPerGroupLimit
    }
}

private func validateText(_ text: String) throws -> Int {
    let length = text.utf8.count
    guard length > 0 else {
        throw LookupRequestError.emptyText
    }
    guard length <= LookupRequestLimits.maximumTextUTF8Length else {
        throw LookupRequestError.textTooLong(
            actual: length,
            maximum: LookupRequestLimits.maximumTextUTF8Length
        )
    }
    return length
}

private func validateCharacterBoundary(_ offset: Int, in text: String) throws {
    let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: offset)
    guard String.Index(utf8Index, within: text) != nil else {
        throw LookupRequestError.offsetIsNotCharacterBoundary(offset)
    }
}

private func validateResultLimit(_ limit: Int) throws {
    guard limit > 0 else {
        throw LookupRequestError.invalidResultLimit(limit)
    }
    guard limit <= LookupRequestLimits.maximumEntriesPerGroup else {
        throw LookupRequestError.resultLimitTooLarge(
            actual: limit,
            maximum: LookupRequestLimits.maximumEntriesPerGroup
        )
    }
}

private func validateResultGroupLimit(_ limit: Int) throws {
    guard limit > 0 else {
        throw LookupRequestError.invalidResultGroupLimit(limit)
    }
    guard limit <= LookupRequestLimits.maximumResultGroups else {
        throw LookupRequestError.resultGroupLimitTooLarge(
            actual: limit,
            maximum: LookupRequestLimits.maximumResultGroups
        )
    }
}
