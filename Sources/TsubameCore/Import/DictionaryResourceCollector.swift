import Foundation

struct DictionaryResourceCollector {
    let limits: DictionaryResourceImportLimits

    func collectAndCopy(
        from sourceRoot: URL,
        to resourcesRoot: URL
    ) throws -> [DictionaryResourceRecord] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: resourcesRoot, withIntermediateDirectories: true)

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        var enumerationError: (any Error)?
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw DictionaryInstallationError.resourceValidationFailed(sourceRoot.path)
        }

        let rootComponents = sourceRoot.standardizedFileURL.pathComponents
        var records: [DictionaryResourceRecord] = []
        var totalBytes: Int64 = 0

        for case let sourceURL as URL in enumerator {
            let values = try sourceURL.resourceValues(forKeys: keys)
            let relativePath = try relativePath(
                for: sourceURL,
                rootComponents: rootComponents
            )

            if values.isSymbolicLink == true {
                throw DictionaryInstallationError.symbolicLinkResource(relativePath)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw DictionaryInstallationError.unsupportedResource(relativePath)
            }
            if isDictionaryDataFile(relativePath) {
                continue
            }

            let logicalPath: DictionaryResourcePath
            do {
                logicalPath = try DictionaryResourcePath(relativePath)
                try validateWindowsPortableComponents(logicalPath.components, path: relativePath)
            } catch let error as DictionaryInstallationError {
                throw error
            } catch {
                throw DictionaryInstallationError.invalidResourcePath(relativePath)
            }

            guard let mediaType = mediaType(forExtension: sourceURL.pathExtension) else {
                throw DictionaryInstallationError.unsupportedResource(relativePath)
            }
            let byteSize = Int64(values.fileSize ?? 0)
            guard byteSize <= limits.maximumResourceBytes else {
                throw DictionaryInstallationError.resourceTooLarge(
                    path: relativePath,
                    actual: byteSize,
                    maximum: limits.maximumResourceBytes
                )
            }
            let (newTotal, overflow) = totalBytes.addingReportingOverflow(byteSize)
            guard !overflow, newTotal <= limits.maximumTotalResourceBytes else {
                throw DictionaryInstallationError.resourcesTooLarge(
                    actual: overflow ? .max : newTotal,
                    maximum: limits.maximumTotalResourceBytes
                )
            }
            totalBytes = newTotal

            guard records.count < limits.maximumResourceCount else {
                throw DictionaryInstallationError.tooManyResources(
                    actual: records.count + 1,
                    maximum: limits.maximumResourceCount
                )
            }

            let destination = logicalPath.components.reduce(resourcesRoot) {
                $0.appending(path: $1)
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: destination)
            records.append(
                DictionaryResourceRecord(
                    logicalPath: logicalPath,
                    storedRelativePath: "resources/\(logicalPath.rawValue)",
                    mediaType: mediaType,
                    byteSize: byteSize
                )
            )
        }

        if let enumerationError {
            throw enumerationError
        }
        return records.sorted { $0.logicalPath.rawValue < $1.logicalPath.rawValue }
    }
}

private extension DictionaryResourceCollector {
    func relativePath(for url: URL, rootComponents: [String]) throws -> String {
        let components = url.standardizedFileURL.pathComponents
        guard components.count > rootComponents.count,
              Array(components.prefix(rootComponents.count)) == rootComponents else {
            throw DictionaryInstallationError.invalidResourcePath(url.path)
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    func isDictionaryDataFile(_ relativePath: String) -> Bool {
        guard !relativePath.contains("/") else {
            return false
        }
        if relativePath == "index.json" {
            return true
        }

        let prefixes = [
            "term_bank_",
            "term_meta_bank_",
            "kanji_bank_",
            "kanji_meta_bank_",
            "tag_bank_"
        ]
        for prefix in prefixes where relativePath.hasPrefix(prefix) && relativePath.hasSuffix(".json") {
            let start = relativePath.index(relativePath.startIndex, offsetBy: prefix.count)
            let end = relativePath.index(relativePath.endIndex, offsetBy: -".json".count)
            if start < end, Int(relativePath[start..<end]) != nil {
                return true
            }
        }
        return false
    }

    func mediaType(forExtension pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "css": "text/css"
        case "png": "image/png"
        case "apng": "image/apng"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "svg": "image/svg+xml"
        default: nil
        }
    }

    func validateWindowsPortableComponents(_ components: [String], path: String) throws {
        for component in components {
            guard !component.hasSuffix("."), !component.hasSuffix(" ") else {
                throw DictionaryInstallationError.invalidResourcePath(path)
            }

            let stem = component
                .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .uppercased()
            if ["CON", "PRN", "AUX", "NUL"].contains(stem) {
                throw DictionaryInstallationError.invalidResourcePath(path)
            }
            if stem.count == 4,
               (stem.hasPrefix("COM") || stem.hasPrefix("LPT")),
               let digit = stem.last,
               digit >= "1", digit <= "9" {
                throw DictionaryInstallationError.invalidResourcePath(path)
            }
        }
    }
}
