import Foundation

enum DictionaryBundleValidator {
    static func validate(
        databaseURL: URL,
        resourcesRoot: URL,
        expectedResources: [DictionaryResourceRecord]
    ) throws {
        try Task.checkCancellation()
        let connection = try SQLiteConnection(url: databaseURL, mode: .readOnly)
        defer { try? connection.close() }

        let storedResources = try loadStoredResources(from: connection)
        let expectedByPath = try resourcesByPath(expectedResources)
        let storedByPath = try resourcesByPath(storedResources)
        guard storedByPath == expectedByPath else {
            throw DictionaryInstallationError.resourceValidationFailed(
                "SQLite resource inventory"
            )
        }

        try validateResourceFiles(
            expectedResources,
            resourcesRoot: resourcesRoot
        )
        try validateStructuredContent(
            connection: connection,
            resourcesByPath: expectedByPath
        )
    }

    static func validateInstalledBundle(
        at bundleURL: URL,
        expectedDictionaryID: UUID
    ) throws -> DictionaryBundleManifest {
        try requireDirectory(bundleURL)
        let manifestURL = bundleURL.appending(path: "manifest.json")
        let databaseURL = bundleURL.appending(path: "dictionary.sqlite")
        let resourcesRoot = bundleURL.appending(
            path: "resources",
            directoryHint: .isDirectory
        )
        try requireRegularFile(manifestURL)
        try requireRegularFile(databaseURL)
        try requireDirectory(resourcesRoot)

        let manifest: DictionaryBundleManifest
        do {
            manifest = try JSONDecoder().decode(
                DictionaryBundleManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw DictionaryInstallationError.invalidExistingManifest(manifestURL)
        }
        guard manifest.manifestVersion == DictionaryBundleManifest.currentVersion,
              manifest.dictionaryID == expectedDictionaryID,
              manifest.dictionarySchemaVersion == DictionaryDatabaseSchema.currentVersion else {
            throw DictionaryInstallationError.invalidExistingManifest(manifestURL)
        }

        let connection = try SQLiteConnection(url: databaseURL, mode: .readOnly)
        defer { try? connection.close() }
        try validateSchemaAndIntegrity(connection)
        let resources = try loadStoredResources(from: connection)
        guard resources.count == manifest.resourceCount,
              try resourceByteTotal(resources) == manifest.totalResourceBytes else {
            throw DictionaryInstallationError.resourceValidationFailed(
                "Manifest resource inventory"
            )
        }
        let resourcesByPath = try resourcesByPath(resources)
        try validateResourceFiles(resources, resourcesRoot: resourcesRoot)
        try validateStructuredContent(
            connection: connection,
            resourcesByPath: resourcesByPath
        )
        return manifest
    }
}

private extension DictionaryBundleValidator {
    static func loadStoredResources(
        from connection: SQLiteConnection
    ) throws -> [DictionaryResourceRecord] {
        let statement = try connection.prepare(
            """
            SELECT logical_path, stored_relative_path, media_type, byte_size
            FROM resource
            ORDER BY logical_path
            """
        )
        defer { statement.finalizeIgnoringErrors() }

        var resources: [DictionaryResourceRecord] = []
        while try statement.step() == .row {
            try Task.checkCancellation()
            guard let logicalPathValue = statement.string(at: 0),
                  let storedRelativePath = statement.string(at: 1),
                  let mediaType = statement.string(at: 2) else {
                throw DictionaryInstallationError.resourceValidationFailed(
                    "SQLite resource row"
                )
            }
            let logicalPath = try DictionaryResourcePath(logicalPathValue)
            guard storedRelativePath == "resources/\(logicalPath.rawValue)" else {
                throw DictionaryInstallationError.resourceValidationFailed(
                    logicalPath.rawValue
                )
            }
            resources.append(DictionaryResourceRecord(
                logicalPath: logicalPath,
                storedRelativePath: storedRelativePath,
                mediaType: mediaType,
                byteSize: statement.integer(at: 3)
            ))
        }
        try statement.finalize()
        return resources
    }

    static func resourcesByPath(
        _ resources: [DictionaryResourceRecord]
    ) throws -> [String: DictionaryResourceRecord] {
        var result: [String: DictionaryResourceRecord] = [:]
        for resource in resources {
            guard result.updateValue(
                resource,
                forKey: resource.logicalPath.rawValue
            ) == nil else {
                throw DictionaryInstallationError.resourceValidationFailed(
                    "Duplicate SQLite resource path"
                )
            }
        }
        return result
    }

    static func resourceByteTotal(
        _ resources: [DictionaryResourceRecord]
    ) throws -> Int64 {
        var total: Int64 = 0
        for resource in resources {
            let (updated, overflow) = total.addingReportingOverflow(resource.byteSize)
            guard resource.byteSize >= 0, !overflow else {
                throw DictionaryInstallationError.resourceValidationFailed(
                    "Invalid SQLite resource size"
                )
            }
            total = updated
        }
        return total
    }

    static func validateResourceFiles(
        _ resources: [DictionaryResourceRecord],
        resourcesRoot: URL
    ) throws {
        for resource in resources {
            try Task.checkCancellation()
            let fileURL = resource.logicalPath.components.reduce(resourcesRoot) {
                $0.appending(path: $1)
            }
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  Int64(values.fileSize ?? -1) == resource.byteSize else {
                throw DictionaryInstallationError.resourceValidationFailed(
                    resource.logicalPath.rawValue
                )
            }
        }
    }

    static func validateStructuredContent(
        connection: SQLiteConnection,
        resourcesByPath: [String: DictionaryResourceRecord]
    ) throws {
        let definitions = try connection.prepare(
            """
            SELECT entry_id, position, content_json
            FROM term_definition
            WHERE kind != 'text'
            """
        )
        defer { definitions.finalizeIgnoringErrors() }
        let decoder = DictionaryGlossaryDecoder()
        while try definitions.step() == .row {
            try Task.checkCancellation()
            guard let data = definitions.data(at: 2) else {
                throw DictionaryStoreError.invalidStoredDefinition
            }
            let context = "entry \(definitions.integer(at: 0)), definition \(definitions.integer(at: 1))"
            do {
                for image in try decoder.decode(data).flatMap(\.images) {
                    guard let resource = resourcesByPath[image.path.rawValue],
                          resource.mediaType.hasPrefix("image/") else {
                        throw DictionaryInstallationError.resourceValidationFailed(
                            "\(context): \(image.path.rawValue)"
                        )
                    }
                }
            } catch {
                throw DictionaryInstallationError.resourceValidationFailed(
                    "\(context): \(error.localizedDescription)"
                )
            }
        }
        try definitions.finalize()
    }

    static func validateSchemaAndIntegrity(
        _ connection: SQLiteConnection
    ) throws {
        let version = try connection.prepare("PRAGMA user_version")
        defer { version.finalizeIgnoringErrors() }
        guard try version.step() == .row else {
            throw DictionaryInstallationError.resourceValidationFailed(
                "SQLite schema version"
            )
        }
        let actualVersion = version.integer(at: 0)
        guard actualVersion == Int64(DictionaryDatabaseSchema.currentVersion) else {
            throw DictionaryStoreError.unsupportedSchemaVersion(
                actual: actualVersion,
                expected: DictionaryDatabaseSchema.currentVersion
            )
        }
        guard try version.step() == .done else {
            throw DictionaryInstallationError.resourceValidationFailed(
                "SQLite schema version"
            )
        }
        try version.finalize()

        let integrity = try connection.prepare("PRAGMA integrity_check")
        defer { integrity.finalizeIgnoringErrors() }
        guard try integrity.step() == .row,
              integrity.string(at: 0) == "ok",
              try integrity.step() == .done else {
            throw DictionaryInstallationError.resourceValidationFailed(
                "SQLite integrity check"
            )
        }
        try integrity.finalize()
    }

    static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw DictionaryInstallationError.resourceValidationFailed(url.path)
        }
    }

    static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw DictionaryInstallationError.resourceValidationFailed(url.path)
        }
    }
}
