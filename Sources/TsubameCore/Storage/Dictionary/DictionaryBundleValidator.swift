import Foundation

enum DictionaryBundleValidator {
    static func validate(
        databaseURL: URL,
        resourcesRoot: URL,
        expectedResources: [DictionaryResourceRecord]
    ) throws {
        let connection = try SQLiteConnection(url: databaseURL, mode: .readOnly)
        defer { try? connection.close() }

        let statement = try connection.prepare(
            """
            SELECT logical_path, stored_relative_path, media_type, byte_size
            FROM resource
            ORDER BY logical_path
            """
        )
        defer { statement.finalizeIgnoringErrors() }

        var storedResources: [DictionaryResourceRecord] = []
        while try statement.step() == .row {
            guard let logicalPathValue = statement.string(at: 0),
                  let storedRelativePath = statement.string(at: 1),
                  let mediaType = statement.string(at: 2) else {
                throw DictionaryInstallationError.resourceValidationFailed("SQLite resource row")
            }
            storedResources.append(
                DictionaryResourceRecord(
                    logicalPath: try DictionaryResourcePath(logicalPathValue),
                    storedRelativePath: storedRelativePath,
                    mediaType: mediaType,
                    byteSize: statement.integer(at: 3)
                )
            )
        }
        try statement.finalize()

        let expectedByPath = Dictionary(
            uniqueKeysWithValues: expectedResources.map { ($0.logicalPath.rawValue, $0) }
        )
        let storedByPath = Dictionary(
            uniqueKeysWithValues: storedResources.map { ($0.logicalPath.rawValue, $0) }
        )
        guard storedByPath == expectedByPath else {
            throw DictionaryInstallationError.resourceValidationFailed("SQLite resource inventory")
        }
        for resource in expectedResources {
            let fileURL = resource.logicalPath.components.reduce(resourcesRoot) {
                $0.appending(path: $1)
            }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  Int64(values.fileSize ?? -1) == resource.byteSize else {
                throw DictionaryInstallationError.resourceValidationFailed(
                    resource.logicalPath.rawValue
                )
            }
        }
    }
}
