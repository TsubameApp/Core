//
//  DictionaryImportSource.swift
//  TsubameCore
//
//  Created by k on 20.08.2026.
//

import Foundation

/// Location of a dictionary archive selected for import.
public struct DictionaryImportSource: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}
