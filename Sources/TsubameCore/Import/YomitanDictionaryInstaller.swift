import Foundation

public struct InstalledDictionaryResult: Sendable, Equatable {
    public let dictionaryID: UUID
    public let bundleURL: URL
    public let databaseURL: URL
    public let resourcesURL: URL
    public let manifest: DictionaryBundleManifest

    public init(
        dictionaryID: UUID,
        bundleURL: URL,
        databaseURL: URL,
        resourcesURL: URL,
        manifest: DictionaryBundleManifest
    ) {
        self.dictionaryID = dictionaryID
        self.bundleURL = bundleURL
        self.databaseURL = databaseURL
        self.resourcesURL = resourcesURL
        self.manifest = manifest
    }
}

/// Installs a complete, immutable dictionary bundle under a caller-supplied data root.
public struct YomitanDictionaryInstaller: Sendable {
    public let layout: DictionaryLibraryLayout
    public let resourceLimits: DictionaryResourceImportLimits

    public init(
        layout: DictionaryLibraryLayout,
        resourceLimits: DictionaryResourceImportLimits = .default
    ) {
        self.layout = layout
        self.resourceLimits = resourceLimits
    }

    public func install(
        from source: DictionaryImportSource,
        dictionaryID: UUID = UUID(),
        importID: UUID = UUID(),
        progress: DictionaryImportProgressHandler? = nil
    ) throws -> InstalledDictionaryResult {
        let totalTimer = DictionaryImportTimer()
        let fileManager = FileManager.default
        let finalBundle = layout.dictionaryBundleURL(for: dictionaryID)
        let stagingBundle = layout.publicationStagingURL(for: importID)
        let workingDirectory = layout.temporaryWorkingURL(for: importID)

        guard !fileManager.fileExists(atPath: finalBundle.path) else {
            throw DictionaryInstallationError.finalBundleAlreadyExists(finalBundle)
        }
        guard !fileManager.fileExists(atPath: stagingBundle.path) else {
            throw DictionaryInstallationError.stagingBundleAlreadyExists(stagingBundle)
        }

        try fileManager.createDirectory(
            at: layout.publicationStagingRootURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: stagingBundle, withIntermediateDirectories: false)

        var shouldRemoveStaging = true
        defer {
            if shouldRemoveStaging {
                try? fileManager.removeItem(at: stagingBundle)
            }
            try? fileManager.removeItem(at: workingDirectory)
        }

        let sourceTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.sourcePreparation))
        let dictionaryDirectory = try prepareSource(
            source,
            workingDirectory: workingDirectory,
            fileManager: fileManager
        )
        progress?(.phaseFinished(
            .sourcePreparation,
            elapsedSeconds: sourceTimer.elapsedSeconds
        ))
        let stagingResources = stagingBundle.appending(
            path: "resources",
            directoryHint: .isDirectory
        )
        let resourcesTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.resourceCopy))
        let resources = try DictionaryResourceCollector(limits: resourceLimits)
            .collectAndCopy(from: dictionaryDirectory, to: stagingResources)
        progress?(.phaseFinished(
            .resourceCopy,
            elapsedSeconds: resourcesTimer.elapsedSeconds
        ))

        let stagingDatabase = stagingBundle.appending(path: "dictionary.sqlite")
        let sqliteResult = try YomitanSQLiteDictionaryImporter(
            temporaryRoot: layout.locations.temporaryRoot
        ).import(
            from: DictionaryImportSource(url: dictionaryDirectory),
            to: stagingDatabase,
            resources: resources,
            progress: progress,
            reportSourcePreparation: false
        )

        let manifestTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.manifest))
        let manifest = makeManifest(
            dictionaryID: dictionaryID,
            sqliteResult: sqliteResult,
            resources: resources
        )
        let manifestURL = stagingBundle.appending(path: "manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        progress?(.phaseFinished(.manifest, elapsedSeconds: manifestTimer.elapsedSeconds))

        let validationTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.bundleValidation))
        try DictionaryBundleValidator.validate(
            databaseURL: stagingDatabase,
            resourcesRoot: stagingResources,
            expectedResources: resources
        )
        let decodedManifest = try JSONDecoder().decode(
            DictionaryBundleManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard decodedManifest == manifest else {
            throw DictionaryInstallationError.manifestValidationFailed
        }
        progress?(.phaseFinished(
            .bundleValidation,
            elapsedSeconds: validationTimer.elapsedSeconds
        ))

        let publicationTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.publication))
        try fileManager.moveItem(at: stagingBundle, to: finalBundle)
        shouldRemoveStaging = false
        progress?(.phaseFinished(
            .publication,
            elapsedSeconds: publicationTimer.elapsedSeconds
        ))
        progress?(.completed(elapsedSeconds: totalTimer.elapsedSeconds))

        return InstalledDictionaryResult(
            dictionaryID: dictionaryID,
            bundleURL: finalBundle,
            databaseURL: layout.dictionaryDatabaseURL(for: dictionaryID),
            resourcesURL: layout.resourcesRootURL(for: dictionaryID),
            manifest: manifest
        )
    }
}

private extension YomitanDictionaryInstaller {
    func prepareSource(
        _ source: DictionaryImportSource,
        workingDirectory: URL,
        fileManager: FileManager
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: source.url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return source.url
        }

        try fileManager.createDirectory(
            at: workingDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try YomitanArchiveExtractor().extract(source, to: workingDirectory)
    }

    func makeManifest(
        dictionaryID: UUID,
        sqliteResult: YomitanSQLiteImportResult,
        resources: [DictionaryResourceRecord]
    ) -> DictionaryBundleManifest {
        let preview = sqliteResult.preview
        return DictionaryBundleManifest(
            dictionaryID: dictionaryID,
            title: preview.index.title,
            revision: preview.index.revision,
            dictionarySchemaVersion: DictionaryDatabaseSchema.currentVersion,
            termCount: preview.totalEntries,
            termMetadataCount: preview.totalTermMetadata,
            kanjiCount: preview.totalKanji,
            kanjiMetadataCount: preview.totalKanjiMetadata,
            tagCount: preview.totalTags,
            definitionCount: sqliteResult.definitionCount,
            lookupKeyCount: sqliteResult.lookupKeyCount,
            resourceCount: resources.count,
            totalResourceBytes: resources.reduce(0) { $0 + $1.byteSize }
        )
    }
}
