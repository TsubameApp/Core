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

public struct DictionaryReplacementRecoveryConflict: Sendable, Equatable {
    public let dictionaryID: UUID
    public let backupURLs: [URL]
    public let finalBundleURL: URL
    public let reason: String

    public init(
        dictionaryID: UUID,
        backupURLs: [URL],
        finalBundleURL: URL,
        reason: String
    ) {
        self.dictionaryID = dictionaryID
        self.backupURLs = backupURLs
        self.finalBundleURL = finalBundleURL
        self.reason = reason
    }
}

public struct DictionaryReplacementRecoveryReport: Sendable, Equatable {
    public let restoredBackups: [URL]
    public let removedStaleBackups: [URL]
    public let conflicts: [DictionaryReplacementRecoveryConflict]
    public let ignoredEntries: [URL]
    public let issues: [DictionaryLibraryCleanupIssue]

    public init(
        restoredBackups: [URL] = [],
        removedStaleBackups: [URL] = [],
        conflicts: [DictionaryReplacementRecoveryConflict] = [],
        ignoredEntries: [URL] = [],
        issues: [DictionaryLibraryCleanupIssue] = []
    ) {
        self.restoredBackups = restoredBackups
        self.removedStaleBackups = removedStaleBackups
        self.conflicts = conflicts
        self.ignoredEntries = ignoredEntries
        self.issues = issues
    }

    public var hasProblems: Bool {
        !conflicts.isEmpty || !issues.isEmpty
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

    public func recoverAbandonedReplacements(
        fileManager: FileManager = .default
    ) -> DictionaryReplacementRecoveryReport {
        let libraryRoot = layout.dictionariesRootURL.standardizedFileURL
        guard fileManager.fileExists(atPath: libraryRoot.path) else {
            return DictionaryReplacementRecoveryReport()
        }

        do {
            let values = try libraryRoot.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return DictionaryReplacementRecoveryReport(issues: [
                    DictionaryLibraryCleanupIssue(
                        url: libraryRoot,
                        message: "Dictionary library root is not a regular directory."
                    ),
                ])
            }
        } catch {
            return DictionaryReplacementRecoveryReport(issues: [
                DictionaryLibraryCleanupIssue(
                    url: libraryRoot,
                    message: error.localizedDescription
                ),
            ])
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: libraryRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ).map(\.standardizedFileURL)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return DictionaryReplacementRecoveryReport(issues: [
                DictionaryLibraryCleanupIssue(
                    url: libraryRoot,
                    message: error.localizedDescription
                ),
            ])
        }

        var candidatesByDictionary: [UUID: [ReplacementBackupCandidate]] = [:]
        var ignored: [URL] = []
        var issues: [DictionaryLibraryCleanupIssue] = []

        for entry in entries where entry.lastPathComponent.hasPrefix(
            Self.replacementBackupPrefix
        ) {
            guard entry.deletingLastPathComponent() == libraryRoot,
                  replacementImportIdentifier(entry.lastPathComponent) != nil else {
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
                let manifestURL = entry.appending(path: "manifest.json")
                let claimedManifest = try JSONDecoder().decode(
                    DictionaryBundleManifest.self,
                    from: Data(contentsOf: manifestURL)
                )
                let manifest = try DictionaryBundleValidator.validateInstalledBundle(
                    at: entry,
                    expectedDictionaryID: claimedManifest.dictionaryID
                )
                candidatesByDictionary[manifest.dictionaryID, default: []].append(
                    ReplacementBackupCandidate(url: entry, manifest: manifest)
                )
            } catch {
                issues.append(DictionaryLibraryCleanupIssue(
                    url: entry,
                    message: error.localizedDescription
                ))
            }
        }

        let existingNames = Set(entries.map(\.lastPathComponent))
        var restored: [URL] = []
        var removed: [URL] = []
        var conflicts: [DictionaryReplacementRecoveryConflict] = []

        for dictionaryID in candidatesByDictionary.keys.sorted(
            by: { $0.uuidString < $1.uuidString }
        ) {
            guard let candidates = candidatesByDictionary[dictionaryID] else {
                continue
            }
            let finalBundle = layout.dictionaryBundleURL(for: dictionaryID)
                .standardizedFileURL
            let finalExists = existingNames.contains(finalBundle.lastPathComponent)

            if !finalExists {
                guard candidates.count == 1, let candidate = candidates.first else {
                    conflicts.append(DictionaryReplacementRecoveryConflict(
                        dictionaryID: dictionaryID,
                        backupURLs: candidates.map(\.url),
                        finalBundleURL: finalBundle,
                        reason: "Multiple valid replacement backups exist and the final bundle is missing."
                    ))
                    continue
                }
                do {
                    try fileManager.moveItem(at: candidate.url, to: finalBundle)
                    restored.append(candidate.url)
                } catch {
                    issues.append(DictionaryLibraryCleanupIssue(
                        url: candidate.url,
                        message: error.localizedDescription
                    ))
                }
                continue
            }

            let finalManifest: DictionaryBundleManifest
            do {
                finalManifest = try DictionaryBundleValidator.validateInstalledBundle(
                    at: finalBundle,
                    expectedDictionaryID: dictionaryID
                )
            } catch {
                conflicts.append(DictionaryReplacementRecoveryConflict(
                    dictionaryID: dictionaryID,
                    backupURLs: candidates.map(\.url),
                    finalBundleURL: finalBundle,
                    reason: "The final dictionary bundle is not valid: \(error.localizedDescription)"
                ))
                continue
            }

            guard candidates.allSatisfy({
                $0.manifest.title == finalManifest.title
            }) else {
                conflicts.append(DictionaryReplacementRecoveryConflict(
                    dictionaryID: dictionaryID,
                    backupURLs: candidates.map(\.url),
                    finalBundleURL: finalBundle,
                    reason: "The replacement backup title does not match the final dictionary."
                ))
                continue
            }

            for candidate in candidates {
                do {
                    try fileManager.removeItem(at: candidate.url)
                    removed.append(candidate.url)
                } catch {
                    issues.append(DictionaryLibraryCleanupIssue(
                        url: candidate.url,
                        message: error.localizedDescription
                    ))
                }
            }
        }

        return DictionaryReplacementRecoveryReport(
            restoredBackups: restored,
            removedStaleBackups: removed,
            conflicts: conflicts,
            ignoredEntries: ignored,
            issues: issues
        )
    }
}

private extension DictionaryLibraryMaintenance {
    static let replacementBackupPrefix = ".replacement-backup-"

    struct ReplacementBackupCandidate {
        let url: URL
        let manifest: DictionaryBundleManifest
    }

    func isCanonicalImportIdentifier(_ component: String) -> Bool {
        guard let identifier = UUID(uuidString: component) else { return false }
        return identifier.uuidString.lowercased() == component
    }

    func replacementImportIdentifier(_ component: String) -> UUID? {
        guard component.hasPrefix(Self.replacementBackupPrefix) else { return nil }
        let suffix = String(component.dropFirst(Self.replacementBackupPrefix.count))
        guard let identifier = UUID(uuidString: suffix),
              identifier.uuidString.lowercased() == suffix else {
            return nil
        }
        return identifier
    }
}
