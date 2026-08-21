//
//  YomitanDictionaryParser.swift
//  TsubameCore
//
//  Created by k on 20.08.2026.
//

/// Parser boundary for a Yomitan-compatible dictionary archive.
public protocol YomitanDictionaryParser {
    func parse(source: DictionaryImportSource) async throws
}
