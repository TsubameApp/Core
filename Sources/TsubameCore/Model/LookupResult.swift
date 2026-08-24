//
//  LookupResult.swift
//  TsubameCore
//
//  Created by k on 21.08.2026.
//

public struct LookupResult: Sendable, Equatable {
    public let sourceRange: UTF8TextRange
    public let entries: [DictionaryEntry]

    public init(sourceRange: UTF8TextRange, entries: [DictionaryEntry]) {
        self.sourceRange = sourceRange
        self.entries = entries
    }
}
