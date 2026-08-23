//
//  YomitanDictionaryParser.swift
//  TsubameCore
//
//  Created by k on 20.08.2026.
//

import Foundation

/// The number of decoded records in one Yomitan bank file.
public struct YomitanBankSummary: Sendable, Equatable {
    public let fileName: String
    public let entryCount: Int
}

/// A lightweight description of a decoded Yomitan dictionary directory.
public struct YomitanDictionaryPreview: Sendable, Equatable {
    public let index: YomitanDictionaryIndex
    public let termBanks: [YomitanBankSummary]
    public let tagBanks: [YomitanBankSummary]

    public var totalEntries: Int {
        termBanks.reduce(0) { $0 + $1.entryCount }
    }

    public var totalTags: Int {
        tagBanks.reduce(0) { $0 + $1.entryCount }
    }
}

/// Parses and validates an unpacked Yomitan-compatible dictionary directory.
public struct YomitanDictionaryParser: Sendable {
    public init() {}

    public func parse(source: DictionaryImportSource) throws -> YomitanDictionaryPreview {
        let directory = source.url
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DictionaryImportError.sourceIsNotDirectory(directory)
        }

        let indexURL = directory.appending(path: "index.json")
        guard fileManager.fileExists(atPath: indexURL.path) else {
            throw DictionaryImportError.missingIndex(directory)
        }

        let decoder = JSONDecoder()
        let index = try decoder.decode(
            YomitanDictionaryIndex.self,
            from: Data(contentsOf: indexURL)
        )
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let termBankURLs = bankFiles(named: "term_bank_", in: files)

        guard !termBankURLs.isEmpty else {
            throw DictionaryImportError.noTermBanks(directory)
        }

        let termBanks = try termBankURLs.map { url in
            let entries = try decoder.decode(
                [YomitanTermEntry].self,
                from: Data(contentsOf: url)
            )
            return YomitanBankSummary(fileName: url.lastPathComponent, entryCount: entries.count)
        }
        let tagBanks = try bankFiles(named: "tag_bank_", in: files).map { url in
            let tags = try decoder.decode(
                [YomitanTag].self,
                from: Data(contentsOf: url)
            )
            return YomitanBankSummary(fileName: url.lastPathComponent, entryCount: tags.count)
        }

        return YomitanDictionaryPreview(
            index: index,
            termBanks: termBanks,
            tagBanks: tagBanks
        )
    }

    private func bankFiles(named prefix: String, in files: [URL]) -> [URL] {
        files
            .filter {
                $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json"
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}
