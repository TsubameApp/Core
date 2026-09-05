import Foundation

public struct DictionaryResolvedResource: Sendable {
    public let fileURL: URL
    public let mediaType: String
    public let byteSize: Int64
}

/// Resolves only inventoried regular files within an immutable installed bundle.
/// Confine use to one executor, like SQLiteDictionaryStore.
public final class DictionaryResourceResolver {
    private let root: URL
    private let connection: SQLiteConnection

    public init(bundleURL: URL) throws {
        guard bundleURL.isFileURL else { throw DictionaryInstallationError.resourceValidationFailed("Non-local bundle") }
        root = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        connection = try SQLiteConnection(url: root.appending(path: "dictionary.sqlite"), mode: .readOnly)
    }

    public func resolve(_ path: DictionaryResourcePath) throws -> DictionaryResolvedResource {
        let statement = try connection.prepare("SELECT stored_relative_path, media_type, byte_size FROM resource WHERE logical_path = ?")
        defer { statement.finalizeIgnoringErrors() }
        try statement.bind(path.rawValue, at: 1)
        guard try statement.step() == .row,
              let stored = statement.string(at: 0), stored == "resources/\(path.rawValue)",
              let type = statement.string(at: 1), type.hasPrefix("image/") else {
            throw DictionaryInstallationError.resourceValidationFailed(path.rawValue)
        }
        let size = statement.integer(at: 2)
        guard size >= 0, size <= 32 * 1_024 * 1_024 else {
            throw DictionaryInstallationError.resourceValidationFailed(path.rawValue)
        }
        var url = root
        for component in ["resources"] + path.components {
            url.append(path: component)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw DictionaryInstallationError.resourceValidationFailed(path.rawValue)
            }
        }
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathComponents.starts(with: root.pathComponents),
              resolved.pathComponents.count > root.pathComponents.count else {
            throw DictionaryInstallationError.resourceValidationFailed(path.rawValue)
        }
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, Int64(values.fileSize ?? -1) == size else {
            throw DictionaryInstallationError.resourceValidationFailed(path.rawValue)
        }
        return DictionaryResolvedResource(fileURL: resolved, mediaType: type, byteSize: size)
    }
}
