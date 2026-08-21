//
//  DictionaryImporter.swift
//  TsubameCore
//
//  Created by k on 20.08.2026.
//

/// Entry point for importing an external dictionary into Tsubame.
public protocol DictionaryImporter {
    func `import`(from source: DictionaryImportSource) async throws
}
