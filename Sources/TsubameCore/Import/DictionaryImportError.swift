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
    case noSupportedBanks(URL)
    case unsupportedFormat
    case invalidDictionary
    case destinationIsNotLocalFile(URL)
    case destinationAlreadyExists(URL)
    case databaseIntegrityCheckFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .sourceIsNotDirectory(let source):
            return "Dictionary source is not a directory: \(source.path)"
        case .missingIndex(let directory):
            return "index.json was not found in \(directory.path)"
        case .noSupportedBanks(let directory):
            return "No supported Yomitan bank files were found in \(directory.path)"
        case .unsupportedFormat:
            return "The dictionary format is not supported."
        case .invalidDictionary:
            return "The dictionary is invalid."
        case .destinationIsNotLocalFile(let destination):
            return "Dictionary database destination is not a local file URL: \(destination.absoluteString)"
        case .destinationAlreadyExists(let destination):
            return "Dictionary database destination already exists: \(destination.path)"
        case .databaseIntegrityCheckFailed(let result):
            return "Dictionary database integrity check failed: \(result)"
        case .cancelled:
            return "Dictionary import was cancelled."
        }
    }
}
