//
//  DictionaryImportError.swift
//  TsubameCore
//
//  Created by k on 20.08.2026.
//

import Foundation

/// Errors that can be reported before or during dictionary import.
public enum DictionaryImportError: LocalizedError {
    case sourceIsNotDirectory(URL)
    case missingIndex(URL)
    case noTermBanks(URL)
    case unsupportedFormat
    case invalidDictionary
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .sourceIsNotDirectory(let source):
            return "Dictionary source is not a directory: \(source.path)"
        case .missingIndex(let directory):
            return "index.json was not found in \(directory.path)"
        case .noTermBanks(let directory):
            return "No term_bank_*.json files were found in \(directory.path)"
        case .unsupportedFormat:
            return "The dictionary format is not supported."
        case .invalidDictionary:
            return "The dictionary is invalid."
        case .cancelled:
            return "Dictionary import was cancelled."
        }
    }
}
