//
//  DictionaryImportError.swift
//  TsubameCore
//
//  Created by k on 20.08.2026.
//

/// Errors that can be reported before or during dictionary import.
public enum DictionaryImportError: Error {
    case unsupportedFormat
    case invalidDictionary
    case cancelled
}
