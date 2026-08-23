import CTsubameZIP
import Foundation

/// Resource limits applied before a Yomitan archive is extracted.
public struct DictionaryArchiveExtractionLimits: Sendable, Equatable {
    public var maximumEntryCount: Int
    public var maximumTotalUncompressedBytes: UInt64
    public var maximumEntryUncompressedBytes: UInt64
    public var maximumPathDepth: Int
    public var maximumPathUTF8Length: Int
    public var maximumComponentUTF8Length: Int

    public init(
        maximumEntryCount: Int = 100_000,
        maximumTotalUncompressedBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        maximumEntryUncompressedBytes: UInt64 = 512 * 1_024 * 1_024,
        maximumPathDepth: Int = 64,
        maximumPathUTF8Length: Int = 1_024,
        maximumComponentUTF8Length: Int = 255
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumTotalUncompressedBytes = maximumTotalUncompressedBytes
        self.maximumEntryUncompressedBytes = maximumEntryUncompressedBytes
        self.maximumPathDepth = maximumPathDepth
        self.maximumPathUTF8Length = maximumPathUTF8Length
        self.maximumComponentUTF8Length = maximumComponentUTF8Length
    }

    public static let `default` = DictionaryArchiveExtractionLimits()
}

public enum DictionaryArchiveExtractionError: LocalizedError, Sendable, Equatable {
    case sourceIsNotLocalFile(URL)
    case sourceIsNotRegularFile(URL)
    case destinationIsNotLocalFile(URL)
    case destinationAlreadyExists(URL)
    case invalidArchive(String)
    case tooManyEntries(actual: Int, maximum: Int)
    case invalidEntryPath(String)
    case duplicateEntryPath(String)
    case unsupportedEntry(String)
    case encryptedEntry(String)
    case entryTooLarge(path: String, actual: UInt64, maximum: UInt64)
    case archiveTooLarge(actual: UInt64, maximum: UInt64)
    case extractionFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .sourceIsNotLocalFile(let url):
            return "Dictionary archive is not a local file URL: \(url.absoluteString)"
        case .sourceIsNotRegularFile(let url):
            return "Dictionary archive is not a regular file: \(url.path)"
        case .destinationIsNotLocalFile(let url):
            return "Extraction destination is not a local file URL: \(url.absoluteString)"
        case .destinationAlreadyExists(let url):
            return "Extraction destination already exists: \(url.path)"
        case .invalidArchive(let reason):
            return "Dictionary archive is invalid: \(reason)"
        case .tooManyEntries(let actual, let maximum):
            return "Dictionary archive has \(actual) entries; the limit is \(maximum)."
        case .invalidEntryPath(let path):
            return "Dictionary archive contains an unsafe path: \(path)"
        case .duplicateEntryPath(let path):
            return "Dictionary archive contains a duplicate or colliding path: \(path)"
        case .unsupportedEntry(let path):
            return "Dictionary archive contains an unsupported entry: \(path)"
        case .encryptedEntry(let path):
            return "Dictionary archive contains an encrypted entry: \(path)"
        case .entryTooLarge(let path, let actual, let maximum):
            return "Archive entry \(path) is \(actual) bytes; the limit is \(maximum)."
        case .archiveTooLarge(let actual, let maximum):
            return "Dictionary archive expands to \(actual) bytes; the limit is \(maximum)."
        case .extractionFailed(let path, let reason):
            return "Could not extract \(path): \(reason)"
        }
    }
}

/// Safely extracts a local Yomitan ZIP archive into a new staging directory.
public struct YomitanArchiveExtractor: Sendable {
    public let limits: DictionaryArchiveExtractionLimits

    public init(limits: DictionaryArchiveExtractionLimits = .default) {
        self.limits = limits
    }

    @discardableResult
    public func extract(_ source: DictionaryImportSource, to destination: URL) throws -> URL {
        guard source.url.isFileURL else {
            throw DictionaryArchiveExtractionError.sourceIsNotLocalFile(source.url)
        }
        guard destination.isFileURL else {
            throw DictionaryArchiveExtractionError.destinationIsNotLocalFile(destination)
        }

        let sourceValues = try? source.url.resourceValues(forKeys: [.isRegularFileKey])
        guard sourceValues?.isRegularFile == true else {
            throw DictionaryArchiveExtractionError.sourceIsNotRegularFile(source.url)
        }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw DictionaryArchiveExtractionError.destinationAlreadyExists(destination)
        }

        var archive: OpaquePointer?
        var openError = [CChar](repeating: 0, count: 256)
        let didOpen = source.url.path.withCString { path in
            tsubame_zip_open(path, &archive, &openError, openError.count)
        }
        guard didOpen != 0, let archive else {
            throw DictionaryArchiveExtractionError.invalidArchive(Self.string(from: openError))
        }
        defer { tsubame_zip_close(archive) }

        let entries = try validatedEntries(in: archive)

        do {
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            do {
                try extract(entries, from: archive, to: destination, fileManager: fileManager)
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
        } catch let error as DictionaryArchiveExtractionError {
            throw error
        } catch {
            try? fileManager.removeItem(at: destination)
            throw DictionaryArchiveExtractionError.extractionFailed(
                path: destination.lastPathComponent,
                reason: error.localizedDescription
            )
        }

        return destination
    }
}

private extension YomitanArchiveExtractor {
    struct Entry {
        enum Kind {
            case file
            case directory
        }

        let index: UInt32
        let path: String
        let components: [String]
        let kind: Kind
        let uncompressedSize: UInt64
    }

    func validatedEntries(in archive: OpaquePointer) throws -> [Entry] {
        let count = Int(tsubame_zip_entry_count(archive))
        guard count <= limits.maximumEntryCount else {
            throw DictionaryArchiveExtractionError.tooManyEntries(
                actual: count,
                maximum: limits.maximumEntryCount
            )
        }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var paths: [String: Entry.Kind] = [:]
        var totalSize: UInt64 = 0

        for offset in 0..<count {
            let index = UInt32(offset)
            let originalPath = try entryName(in: archive, at: index)
            var info = tsubame_zip_entry_info()
            guard tsubame_zip_entry_get_info(archive, index, &info) != 0 else {
                throw invalidArchiveError(from: archive)
            }

            guard info.encrypted == 0 else {
                throw DictionaryArchiveExtractionError.encryptedEntry(originalPath)
            }
            guard info.supported != 0 else {
                throw DictionaryArchiveExtractionError.unsupportedEntry(originalPath)
            }

            let kind: Entry.Kind
            switch info.kind {
            case TSUBAME_ZIP_ENTRY_FILE:
                kind = .file
            case TSUBAME_ZIP_ENTRY_DIRECTORY:
                kind = .directory
            case TSUBAME_ZIP_ENTRY_SYMLINK, TSUBAME_ZIP_ENTRY_OTHER:
                throw DictionaryArchiveExtractionError.unsupportedEntry(originalPath)
            default:
                throw DictionaryArchiveExtractionError.unsupportedEntry(originalPath)
            }

            let path = kind == .directory && originalPath.hasSuffix("/")
                ? String(originalPath.dropLast())
                : originalPath
            let components = try validatedPathComponents(path)
            let canonicalEntryPath = canonicalPath(for: components)

            guard paths[canonicalEntryPath] == nil else {
                throw DictionaryArchiveExtractionError.duplicateEntryPath(path)
            }

            for parentDepth in 1..<components.count {
                let parent = canonicalPath(for: Array(components.prefix(parentDepth)))
                if case .file? = paths[parent] {
                    throw DictionaryArchiveExtractionError.duplicateEntryPath(path)
                }
            }

            if kind == .file {
                let descendantPrefix = canonicalEntryPath + "/"
                guard !paths.keys.contains(where: { $0.hasPrefix(descendantPrefix) }) else {
                    throw DictionaryArchiveExtractionError.duplicateEntryPath(path)
                }
            }

            guard info.uncompressed_size <= limits.maximumEntryUncompressedBytes else {
                throw DictionaryArchiveExtractionError.entryTooLarge(
                    path: path,
                    actual: info.uncompressed_size,
                    maximum: limits.maximumEntryUncompressedBytes
                )
            }
            let (newTotal, overflow) = totalSize.addingReportingOverflow(info.uncompressed_size)
            guard !overflow, newTotal <= limits.maximumTotalUncompressedBytes else {
                throw DictionaryArchiveExtractionError.archiveTooLarge(
                    actual: overflow ? .max : newTotal,
                    maximum: limits.maximumTotalUncompressedBytes
                )
            }
            totalSize = newTotal

            let entry = Entry(
                index: index,
                path: path,
                components: components,
                kind: kind,
                uncompressedSize: info.uncompressed_size
            )
            paths[canonicalEntryPath] = kind
            entries.append(entry)
        }

        return entries
    }

    func validatedPathComponents(_ path: String) throws -> [String] {
        guard !path.isEmpty,
              path.utf8.count <= limits.maximumPathUTF8Length,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f })
        else {
            throw DictionaryArchiveExtractionError.invalidEntryPath(path)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count <= limits.maximumPathDepth,
              components.allSatisfy({ component in
                  !component.isEmpty
                      && component != "."
                      && component != ".."
                      && component.utf8.count <= limits.maximumComponentUTF8Length
                      && !component.hasSuffix(".")
                      && !component.hasSuffix(" ")
                      && !Self.isWindowsDeviceName(component)
              })
        else {
            throw DictionaryArchiveExtractionError.invalidEntryPath(path)
        }
        return components
    }

    func canonicalPath(for components: [String]) -> String {
        components
            .map { $0.precomposedStringWithCanonicalMapping.lowercased() }
            .joined(separator: "/")
    }

    func entryName(in archive: OpaquePointer, at index: UInt32) throws -> String {
        let size = Int(tsubame_zip_entry_name_size(archive, index))
        guard size > 1 else {
            throw DictionaryArchiveExtractionError.invalidEntryPath("")
        }

        var bytes = [UInt8](repeating: 0, count: size)
        let success = bytes.withUnsafeMutableBytes { rawBuffer in
            tsubame_zip_entry_name(
                archive,
                index,
                rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self),
                UInt32(size)
            )
        }
        guard success != 0, bytes.last == 0,
              let name = String(bytes: bytes.dropLast(), encoding: .utf8)
        else {
            throw DictionaryArchiveExtractionError.invalidEntryPath("<invalid UTF-8>")
        }
        return name
    }

    func extract(
        _ entries: [Entry],
        from archive: OpaquePointer,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        for entry in entries {
            let output = entry.components.reduce(destination) {
                $0.appendingPathComponent($1, isDirectory: false)
            }

            switch entry.kind {
            case .directory:
                try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
            case .file:
                try fileManager.createDirectory(
                    at: output.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard fileManager.createFile(atPath: output.path, contents: nil) else {
                    throw DictionaryArchiveExtractionError.extractionFailed(
                        path: entry.path,
                        reason: "Could not create output file"
                    )
                }
                try extractFile(entry, from: archive, to: output)
            }
        }
    }

    func extractFile(_ entry: Entry, from archive: OpaquePointer, to output: URL) throws {
        guard let iterator = tsubame_zip_extract_begin(archive, entry.index) else {
            throw DictionaryArchiveExtractionError.extractionFailed(
                path: entry.path,
                reason: archiveErrorMessage(from: archive)
            )
        }

        let file: FileHandle
        do {
            file = try FileHandle(forWritingTo: output)
        } catch {
            _ = tsubame_zip_extract_finish(iterator)
            throw error
        }
        var written: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var readFailed = false

        do {
            while written < entry.uncompressedSize {
                let remaining = entry.uncompressedSize - written
                let requestedCount = min(buffer.count, Int(remaining))
                let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                    tsubame_zip_extract_read(iterator, rawBuffer.baseAddress, requestedCount)
                }
                guard bytesRead > 0 else {
                    readFailed = true
                    break
                }
                try file.write(contentsOf: buffer.prefix(bytesRead))
                written += UInt64(bytesRead)
            }
            try file.close()
        } catch {
            try? file.close()
            _ = tsubame_zip_extract_finish(iterator)
            throw error
        }

        let didFinish = tsubame_zip_extract_finish(iterator) != 0
        guard !readFailed, written == entry.uncompressedSize, didFinish else {
            throw DictionaryArchiveExtractionError.extractionFailed(
                path: entry.path,
                reason: archiveErrorMessage(from: archive)
            )
        }
    }

    func invalidArchiveError(from archive: OpaquePointer) -> DictionaryArchiveExtractionError {
        .invalidArchive(archiveErrorMessage(from: archive))
    }

    func archiveErrorMessage(from archive: OpaquePointer) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        tsubame_zip_last_error(archive, &buffer, buffer.count)
        return Self.string(from: buffer)
    }

    static func string(from buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { pointer in
            String(cString: pointer.baseAddress!)
        }
    }

    static func isWindowsDeviceName(_ component: String) -> Bool {
        let stem = component.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .uppercased()
        if ["CON", "PRN", "AUX", "NUL"].contains(stem) {
            return true
        }
        if stem.count == 4,
           (stem.hasPrefix("COM") || stem.hasPrefix("LPT")),
           let digit = stem.last,
           digit >= "1", digit <= "9" {
            return true
        }
        return false
    }
}
