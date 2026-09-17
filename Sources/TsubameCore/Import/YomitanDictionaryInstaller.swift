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
    private let replaceBundle: @Sendable (URL, URL, String) throws -> Void

    public init(
        layout: DictionaryLibraryLayout,
        resourceLimits: DictionaryResourceImportLimits = .default
    ) {
        self.layout = layout
        self.resourceLimits = resourceLimits
        replaceBundle = { originalURL, replacementURL, backupName in
            _ = try FileManager.default.replaceItemAt(
                originalURL,
                withItemAt: replacementURL,
                backupItemName: backupName,
                options: [.withoutDeletingBackupItem]
            )
        }
    }

    init(
        layout: DictionaryLibraryLayout,
        resourceLimits: DictionaryResourceImportLimits = .default,
        replaceBundle: @escaping @Sendable (URL, URL, String) throws -> Void
    ) {
        self.layout = layout
        self.resourceLimits = resourceLimits
        self.replaceBundle = replaceBundle
    }

    public func install(
        from source: DictionaryImportSource,
        dictionaryID: UUID = UUID(),
        importID: UUID = UUID(),
        progress: DictionaryImportProgressHandler? = nil
    ) throws -> InstalledDictionaryResult {
        try Task.checkCancellation()
        let totalTimer = DictionaryImportTimer()
        let fileManager = FileManager.default
        let finalBundle = layout.dictionaryBundleURL(for: dictionaryID)

        guard !fileManager.fileExists(atPath: finalBundle.path) else {
            throw DictionaryInstallationError.finalBundleAlreadyExists(finalBundle)
        }
        let staged = try buildStagedBundle(
            from: source,
            dictionaryID: dictionaryID,
            importID: importID,
            progress: progress
        )
        defer { try? fileManager.removeItem(at: staged.bundleURL) }

        let publicationTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.publication))
        try Task.checkCancellation()
        try fileManager.moveItem(at: staged.bundleURL, to: finalBundle)
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
            manifest: staged.manifest
        )
    }

    public func replace(
        dictionaryID: UUID,
        from source: DictionaryImportSource,
        importID: UUID = UUID(),
        progress: DictionaryImportProgressHandler? = nil
    ) throws -> InstalledDictionaryResult {
        try Task.checkCancellation()
        let totalTimer = DictionaryImportTimer()
        let fileManager = FileManager.default
        let finalBundle = layout.dictionaryBundleURL(for: dictionaryID)
        let existingManifestURL = layout.dictionaryManifestURL(for: dictionaryID)

        guard fileManager.fileExists(atPath: finalBundle.path) else {
            throw DictionaryInstallationError.finalBundleNotFound(finalBundle)
        }
        let existingManifest: DictionaryBundleManifest
        do {
            existingManifest = try JSONDecoder().decode(
                DictionaryBundleManifest.self,
                from: Data(contentsOf: existingManifestURL)
            )
        } catch {
            throw DictionaryInstallationError.invalidExistingManifest(existingManifestURL)
        }
        guard existingManifest.dictionaryID == dictionaryID,
              existingManifest.manifestVersion == DictionaryBundleManifest.currentVersion else {
            throw DictionaryInstallationError.invalidExistingManifest(existingManifestURL)
        }

        let staged = try buildStagedBundle(
            from: source,
            dictionaryID: dictionaryID,
            importID: importID,
            progress: progress
        )
        defer { try? fileManager.removeItem(at: staged.bundleURL) }

        guard staged.manifest.title == existingManifest.title else {
            throw DictionaryInstallationError.replacementTitleMismatch(
                expected: existingManifest.title,
                actual: staged.manifest.title
            )
        }

        let backupName = ".replacement-backup-\(importID.uuidString.lowercased())"
        let backupURL = layout.dictionariesRootURL.appending(
            path: backupName,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            throw DictionaryInstallationError.replacementBackupAlreadyExists(backupURL)
        }

        let publicationTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.publication))
        try Task.checkCancellation()
        do {
            try replaceBundle(finalBundle, staged.bundleURL, backupName)
        } catch {
            try rollbackReplacementIfNeeded(
                finalBundle: finalBundle,
                backupBundle: backupURL,
                fileManager: fileManager
            )
            throw error
        }

        do {
            let publishedManifest = try JSONDecoder().decode(
                DictionaryBundleManifest.self,
                from: Data(contentsOf: existingManifestURL)
            )
            guard publishedManifest == staged.manifest else {
                throw DictionaryInstallationError.manifestValidationFailed
            }
        } catch {
            try rollbackReplacementIfNeeded(
                finalBundle: finalBundle,
                backupBundle: backupURL,
                fileManager: fileManager,
                replacingPublishedBundle: true
            )
            throw error
        }

        try? fileManager.removeItem(at: backupURL)
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
            manifest: staged.manifest
        )
    }
}

private extension YomitanDictionaryInstaller {
    struct StagedDictionaryBundle {
        let bundleURL: URL
        let manifest: DictionaryBundleManifest
    }

    func buildStagedBundle(
        from source: DictionaryImportSource,
        dictionaryID: UUID,
        importID: UUID,
        progress: DictionaryImportProgressHandler?
    ) throws -> StagedDictionaryBundle {
        let fileManager = FileManager.default
        let stagingBundle = layout.publicationStagingURL(for: importID)
        let workingDirectory = layout.temporaryWorkingURL(for: importID)
        guard !fileManager.fileExists(atPath: stagingBundle.path) else {
            throw DictionaryInstallationError.stagingBundleAlreadyExists(stagingBundle)
        }

        try fileManager.createDirectory(
            at: layout.publicationStagingRootURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: stagingBundle, withIntermediateDirectories: false)

        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: stagingBundle)
            }
            try? fileManager.removeItem(at: workingDirectory)
        }

        let sourceTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.sourcePreparation))
        try Task.checkCancellation()
        let dictionaryDirectory = try prepareSource(
            source,
            workingDirectory: workingDirectory,
            fileManager: fileManager
        )
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        let resources = try DictionaryResourceCollector(limits: resourceLimits)
            .collectAndCopy(from: dictionaryDirectory, to: stagingResources)
        try Task.checkCancellation()
        progress?(.phaseFinished(
            .resourceCopy,
            elapsedSeconds: resourcesTimer.elapsedSeconds
        ))

        let stagingDatabase = stagingBundle.appending(path: "dictionary.sqlite")
        try Task.checkCancellation()
        let sqliteResult = try YomitanSQLiteDictionaryImporter(
            temporaryRoot: layout.locations.temporaryRoot
        ).import(
            from: DictionaryImportSource(url: dictionaryDirectory),
            to: stagingDatabase,
            resources: resources,
            progress: progress,
            reportSourcePreparation: false
        )
        try Task.checkCancellation()

        let manifestTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.manifest))
        try Task.checkCancellation()
        let manifest = makeManifest(
            dictionaryID: dictionaryID,
            sqliteResult: sqliteResult,
            resources: resources
        )
        let manifestURL = stagingBundle.appending(path: "manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try Task.checkCancellation()
        progress?(.phaseFinished(.manifest, elapsedSeconds: manifestTimer.elapsedSeconds))

        let validationTimer = DictionaryImportTimer()
        progress?(.phaseStarted(.bundleValidation))
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        progress?(.phaseFinished(
            .bundleValidation,
            elapsedSeconds: validationTimer.elapsedSeconds
        ))

        completed = true
        return StagedDictionaryBundle(bundleURL: stagingBundle, manifest: manifest)
    }

    func rollbackReplacementIfNeeded(
        finalBundle: URL,
        backupBundle: URL,
        fileManager: FileManager,
        replacingPublishedBundle: Bool = false
    ) throws {
        guard fileManager.fileExists(atPath: backupBundle.path) else { return }
        do {
            if replacingPublishedBundle || fileManager.fileExists(atPath: finalBundle.path) {
                try fileManager.removeItem(at: finalBundle)
            }
            try fileManager.moveItem(at: backupBundle, to: finalBundle)
        } catch {
            throw DictionaryInstallationError.replacementRecoveryFailed(finalBundle)
        }
    }

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
