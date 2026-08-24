import Foundation

public struct YomitanSQLiteImportResult: Sendable, Equatable {
    public let databaseURL: URL
    public let preview: YomitanDictionaryPreview
    public let definitionCount: Int
    public let lookupKeyCount: Int

    public init(
        databaseURL: URL,
        preview: YomitanDictionaryPreview,
        definitionCount: Int,
        lookupKeyCount: Int
    ) {
        self.databaseURL = databaseURL
        self.preview = preview
        self.definitionCount = definitionCount
        self.lookupKeyCount = lookupKeyCount
    }
}

/// Converts a local Yomitan ZIP or unpacked directory into one SQLite database.
public struct YomitanSQLiteDictionaryImporter: Sendable {
    public let temporaryRoot: URL

    public init(temporaryRoot: URL) {
        self.temporaryRoot = temporaryRoot
    }

    public func `import`(
        from source: DictionaryImportSource,
        to databaseURL: URL,
        progress: DictionaryImportProgressHandler? = nil
    ) throws -> YomitanSQLiteImportResult {
        let totalTimer = DictionaryImportTimer()
        let result = try `import`(
            from: source,
            to: databaseURL,
            resources: [],
            progress: progress,
            reportSourcePreparation: true
        )
        progress?(.completed(elapsedSeconds: totalTimer.elapsedSeconds))
        return result
    }

    func `import`(
        from source: DictionaryImportSource,
        to databaseURL: URL,
        resources: [DictionaryResourceRecord],
        progress: DictionaryImportProgressHandler? = nil,
        reportSourcePreparation: Bool = true
    ) throws -> YomitanSQLiteImportResult {
        let fileManager = FileManager.default
        guard databaseURL.isFileURL else {
            throw DictionaryImportError.destinationIsNotLocalFile(databaseURL)
        }
        guard !fileManager.fileExists(atPath: databaseURL.path) else {
            throw DictionaryImportError.destinationAlreadyExists(databaseURL)
        }

        var isDirectory: ObjCBool = false
        let sourceExists = fileManager.fileExists(
            atPath: source.url.path,
            isDirectory: &isDirectory
        )

        let sourceTimer = DictionaryImportTimer()
        if reportSourcePreparation {
            progress?(.phaseStarted(.sourcePreparation))
        }

        let dictionaryDirectory: URL
        var extractedDirectory: URL?
        if sourceExists, isDirectory.boolValue {
            dictionaryDirectory = source.url
        } else {
            let extractionURL = temporaryRoot
                .appending(path: "Tsubame", directoryHint: .isDirectory)
                .appending(
                    path: "sqlite-import-\(UUID().uuidString.lowercased())",
                    directoryHint: .isDirectory
                )
            try fileManager.createDirectory(
                at: extractionURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            dictionaryDirectory = try YomitanArchiveExtractor().extract(
                source,
                to: extractionURL
            )
            extractedDirectory = extractionURL
        }
        if reportSourcePreparation {
            progress?(.phaseFinished(
                .sourcePreparation,
                elapsedSeconds: sourceTimer.elapsedSeconds
            ))
        }
        defer {
            if let extractedDirectory {
                try? fileManager.removeItem(at: extractedDirectory)
            }
        }

        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            return try buildDatabase(
                from: dictionaryDirectory,
                at: databaseURL,
                resources: resources,
                progress: progress
            )
        } catch {
            removeDatabaseFiles(at: databaseURL, fileManager: fileManager)
            throw error
        }
    }
}

private extension YomitanSQLiteDictionaryImporter {
    struct ImportFiles {
        let index: URL
        let termBanks: [URL]
        let termMetadataBanks: [URL]
        let kanjiBanks: [URL]
        let kanjiMetadataBanks: [URL]
        let tagBanks: [URL]
    }

    func buildDatabase(
        from directory: URL,
        at databaseURL: URL,
        resources: [DictionaryResourceRecord],
        progress: DictionaryImportProgressHandler?
    ) throws -> YomitanSQLiteImportResult {
        let files = try importFiles(in: directory)
        let indexData = try Data(contentsOf: files.index)
        let decoder = JSONDecoder()
        let index = try decoder.decode(YomitanDictionaryIndex.self, from: indexData)
        guard index.format == 3 else {
            throw DictionaryImportError.unsupportedFormat
        }
        guard !files.termBanks.isEmpty
                || !files.termMetadataBanks.isEmpty
                || !files.kanjiBanks.isEmpty
                || !files.kanjiMetadataBanks.isEmpty else {
            throw DictionaryImportError.noSupportedBanks(directory)
        }

        var termSummaries: [YomitanBankSummary] = []
        var termMetadataSummaries: [YomitanBankSummary] = []
        var kanjiSummaries: [YomitanBankSummary] = []
        var kanjiMetadataSummaries: [YomitanBankSummary] = []
        var tagSummaries: [YomitanBankSummary] = []
        let totalBanks = files.termBanks.count
            + files.termMetadataBanks.count
            + files.kanjiBanks.count
            + files.kanjiMetadataBanks.count
            + files.tagBanks.count
        var currentBank = 0

        let writer = try DictionaryDatabaseWriter(url: databaseURL)
        let counts = try writer.build(
            index: index,
            indexData: indexData,
            resources: resources,
            progress: progress
        ) { session in
            for (bankOrder, url) in files.termBanks.enumerated() {
                currentBank += 1
                let timer = DictionaryImportTimer()
                progress?(.bankStarted(
                    kind: .term,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks
                ))
                let entries = try decoder.decode(
                    [YomitanTermEntry].self,
                    from: Data(contentsOf: url)
                )
                try session.insertTerms(entries, bankOrder: bankOrder)
                termSummaries.append(summary(for: url, count: entries.count))
                progress?(.bankFinished(
                    kind: .term,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks,
                    entryCount: entries.count,
                    elapsedSeconds: timer.elapsedSeconds
                ))
            }

            for (bankOrder, url) in files.termMetadataBanks.enumerated() {
                currentBank += 1
                let timer = DictionaryImportTimer()
                progress?(.bankStarted(
                    kind: .termMetadata,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks
                ))
                let entries = try decoder.decode(
                    [YomitanTermMetadata].self,
                    from: Data(contentsOf: url)
                )
                try session.insertTermMetadata(entries, bankOrder: bankOrder)
                termMetadataSummaries.append(summary(for: url, count: entries.count))
                progress?(.bankFinished(
                    kind: .termMetadata,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks,
                    entryCount: entries.count,
                    elapsedSeconds: timer.elapsedSeconds
                ))
            }

            for (bankOrder, url) in files.kanjiBanks.enumerated() {
                currentBank += 1
                let timer = DictionaryImportTimer()
                progress?(.bankStarted(
                    kind: .kanji,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks
                ))
                let entries = try decoder.decode(
                    [YomitanKanjiEntry].self,
                    from: Data(contentsOf: url)
                )
                try session.insertKanji(entries, bankOrder: bankOrder)
                kanjiSummaries.append(summary(for: url, count: entries.count))
                progress?(.bankFinished(
                    kind: .kanji,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks,
                    entryCount: entries.count,
                    elapsedSeconds: timer.elapsedSeconds
                ))
            }

            for (bankOrder, url) in files.kanjiMetadataBanks.enumerated() {
                currentBank += 1
                let timer = DictionaryImportTimer()
                progress?(.bankStarted(
                    kind: .kanjiMetadata,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks
                ))
                let entries = try decoder.decode(
                    [YomitanKanjiMetadata].self,
                    from: Data(contentsOf: url)
                )
                try session.insertKanjiMetadata(entries, bankOrder: bankOrder)
                kanjiMetadataSummaries.append(summary(for: url, count: entries.count))
                progress?(.bankFinished(
                    kind: .kanjiMetadata,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks,
                    entryCount: entries.count,
                    elapsedSeconds: timer.elapsedSeconds
                ))
            }

            for (bankOrder, url) in files.tagBanks.enumerated() {
                currentBank += 1
                let timer = DictionaryImportTimer()
                progress?(.bankStarted(
                    kind: .tag,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks
                ))
                let entries = try decoder.decode(
                    [YomitanTag].self,
                    from: Data(contentsOf: url)
                )
                try session.insertTags(entries, bankOrder: bankOrder)
                tagSummaries.append(summary(for: url, count: entries.count))
                progress?(.bankFinished(
                    kind: .tag,
                    fileName: url.lastPathComponent,
                    index: currentBank,
                    total: totalBanks,
                    entryCount: entries.count,
                    elapsedSeconds: timer.elapsedSeconds
                ))
            }

            return (session.definitionCount, session.lookupKeyCount)
        }

        let preview = YomitanDictionaryPreview(
            index: index,
            termBanks: termSummaries,
            termMetadataBanks: termMetadataSummaries,
            kanjiBanks: kanjiSummaries,
            kanjiMetadataBanks: kanjiMetadataSummaries,
            tagBanks: tagSummaries
        )
        return YomitanSQLiteImportResult(
            databaseURL: databaseURL,
            preview: preview,
            definitionCount: counts.0,
            lookupKeyCount: counts.1
        )
    }

    func importFiles(in directory: URL) throws -> ImportFiles {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw DictionaryImportError.sourceIsNotDirectory(directory)
        }

        let index = directory.appending(path: "index.json")
        guard FileManager.default.fileExists(atPath: index.path) else {
            throw DictionaryImportError.missingIndex(directory)
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return ImportFiles(
            index: index,
            termBanks: bankFiles(prefix: "term_bank_", in: files),
            termMetadataBanks: bankFiles(prefix: "term_meta_bank_", in: files),
            kanjiBanks: bankFiles(prefix: "kanji_bank_", in: files),
            kanjiMetadataBanks: bankFiles(prefix: "kanji_meta_bank_", in: files),
            tagBanks: bankFiles(prefix: "tag_bank_", in: files)
        )
    }

    func bankFiles(prefix: String, in files: [URL]) -> [URL] {
        files.compactMap { url -> (number: Int, url: URL)? in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".json") else {
                return nil
            }
            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -".json".count)
            guard start < end, let number = Int(name[start..<end]) else {
                return nil
            }
            return (number, url)
        }
        .sorted {
            if $0.number != $1.number {
                return $0.number < $1.number
            }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
        .map(\.url)
    }

    func summary(for url: URL, count: Int) -> YomitanBankSummary {
        YomitanBankSummary(fileName: url.lastPathComponent, entryCount: count)
    }

    func removeDatabaseFiles(at url: URL, fileManager: FileManager) {
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? fileManager.removeItem(atPath: url.path + suffix)
        }
    }
}
