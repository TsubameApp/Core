import Foundation

public struct DictionaryLibraryCleanupIssue: Sendable, Equatable {
    public let url: URL
    public let message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct DictionaryLibraryCleanupReport: Sendable, Equatable {
    public let removedStagingDirectories: [URL]
    public let ignoredEntries: [URL]
    public let issues: [DictionaryLibraryCleanupIssue]

    public init(
        removedStagingDirectories: [URL] = [],
        ignoredEntries: [URL] = [],
        issues: [DictionaryLibraryCleanupIssue] = []
    ) {
        self.removedStagingDirectories = removedStagingDirectories
        self.ignoredEntries = ignoredEntries
        self.issues = issues
    }

    public var removedCount: Int {
        removedStagingDirectories.count
    }

    public var hasIssues: Bool {
        !issues.isEmpty
    }
}

/// Performs conservative maintenance on a caller-owned dictionary library.
///
/// Callers must ensure that no imports are active while cleanup runs. Only
/// direct child directories in `.staging` whose names exactly match the
/// importer's canonical UUID format are removed. Unknown entries and symbolic
/// links are preserved and reported.
public struct DictionaryLibraryMaintenance: Sendable {
    public let layout: DictionaryLibraryLayout

    public init(layout: DictionaryLibraryLayout) {
        self.layout = layout
    }

    public func cleanupAbandonedImports(
        fileManager: FileManager = .default
    ) -> DictionaryLibraryCleanupReport {
        let stagingRoot = layout.publicationStagingRootURL.standardizedFileURL
        guard fileManager.fileExists(atPath: stagingRoot.path) else {
            return DictionaryLibraryCleanupReport()
        }

        do {
            let rootValues = try stagingRoot.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard rootValues.isDirectory == true,
                  rootValues.isSymbolicLink != true else {
                return DictionaryLibraryCleanupReport(
                    ignoredEntries: [stagingRoot]
                )
            }
        } catch {
            return DictionaryLibraryCleanupReport(issues: [
                DictionaryLibraryCleanupIssue(
                    url: stagingRoot,
                    message: error.localizedDescription
                ),
            ])
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: stagingRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return DictionaryLibraryCleanupReport(issues: [
                DictionaryLibraryCleanupIssue(
                    url: stagingRoot,
                    message: error.localizedDescription
                ),
            ])
        }

        var removed: [URL] = []
        var ignored: [URL] = []
        var issues: [DictionaryLibraryCleanupIssue] = []

        for entry in entries {
            let entry = entry.standardizedFileURL
            guard entry.deletingLastPathComponent() == stagingRoot,
                  isCanonicalImportIdentifier(entry.lastPathComponent) else {
                ignored.append(entry)
                continue
            }

            do {
                let values = try entry.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    ignored.append(entry)
                    continue
                }
                try fileManager.removeItem(at: entry)
                removed.append(entry)
            } catch {
                issues.append(DictionaryLibraryCleanupIssue(
                    url: entry,
                    message: error.localizedDescription
                ))
            }
        }

        return DictionaryLibraryCleanupReport(
            removedStagingDirectories: removed,
            ignoredEntries: ignored,
            issues: issues
        )
    }
}

private extension DictionaryLibraryMaintenance {
    func isCanonicalImportIdentifier(_ component: String) -> Bool {
        guard let identifier = UUID(uuidString: component) else { return false }
        return identifier.uuidString.lowercased() == component
    }
}
