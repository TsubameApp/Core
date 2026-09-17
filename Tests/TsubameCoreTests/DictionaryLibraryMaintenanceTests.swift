import Foundation
import Testing
@testable import TsubameCore

struct DictionaryLibraryMaintenanceTests {
    @Test
    func missingStagingRootNeedsNoCleanup() {
        let layout = makeLayout(root: temporaryRoot())

        let report = DictionaryLibraryMaintenance(layout: layout)
            .cleanupAbandonedImports()

        #expect(report == DictionaryLibraryCleanupReport())
    }

    @Test
    func removesOnlyCanonicalStagingDirectories() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let importID = UUID()
        let abandoned = layout.publicationStagingURL(for: importID)
        let nested = abandoned.appending(path: "resources", directoryHint: .isDirectory)
        let unknownDirectory = layout.publicationStagingRootURL.appending(
            path: "keep-me",
            directoryHint: .isDirectory
        )
        let unknownFile = layout.publicationStagingRootURL.appending(path: "notes.txt")
        let installedID = UUID()
        let installed = layout.dictionaryBundleURL(for: installedID)

        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: nested.appending(path: "asset.bin"))
        try fileManager.createDirectory(at: unknownDirectory, withIntermediateDirectories: true)
        try Data("leave".utf8).write(to: unknownFile)
        try fileManager.createDirectory(at: installed, withIntermediateDirectories: true)

        let report = DictionaryLibraryMaintenance(layout: layout)
            .cleanupAbandonedImports()

        #expect(report.removedStagingDirectories.map(\.path) == [abandoned.path])
        #expect(Set(report.ignoredEntries.map(\.path)) == Set([
            unknownDirectory.path,
            unknownFile.path,
        ]))
        #expect(report.issues.isEmpty)
        #expect(!fileManager.fileExists(atPath: abandoned.path))
        #expect(fileManager.fileExists(atPath: unknownDirectory.path))
        #expect(fileManager.fileExists(atPath: unknownFile.path))
        #expect(fileManager.fileExists(atPath: installed.path))
    }

    @Test
    func preservesSymbolicLinksWithCanonicalNames() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let outside = root.appending(path: "outside", directoryHint: .isDirectory)
        let link = layout.publicationStagingURL(for: UUID())
        try fileManager.createDirectory(
            at: layout.publicationStagingRootURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: outside.appending(path: "value.txt"))
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outside)

        let report = DictionaryLibraryMaintenance(layout: layout)
            .cleanupAbandonedImports()

        #expect(report.removedStagingDirectories.isEmpty)
        #expect(report.ignoredEntries.map(\.path) == [link.path])
        #expect(report.issues.isEmpty)
        #expect(fileManager.fileExists(atPath: link.path))
        #expect(fileManager.fileExists(atPath: outside.appending(path: "value.txt").path))
    }

    @Test
    func refusesASymbolicLinkStagingRoot() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let outside = root.appending(path: "outside", directoryHint: .isDirectory)
        let outsideImport = outside.appending(
            path: UUID().uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: outsideImport, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: layout.dictionariesRootURL,
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            at: layout.publicationStagingRootURL,
            withDestinationURL: outside
        )

        let report = DictionaryLibraryMaintenance(layout: layout)
            .cleanupAbandonedImports()

        #expect(report.removedStagingDirectories.isEmpty)
        #expect(report.ignoredEntries.map(\.path) == [
            layout.publicationStagingRootURL.path,
        ])
        #expect(report.issues.isEmpty)
        #expect(fileManager.fileExists(atPath: outsideImport.path))
    }

    @Test
    func leavesStagingRootReadyForTheNextImport() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        try fileManager.createDirectory(
            at: layout.publicationStagingURL(for: UUID()),
            withIntermediateDirectories: true
        )

        let report = DictionaryLibraryMaintenance(layout: layout)
            .cleanupAbandonedImports()

        #expect(report.removedCount == 1)
        #expect(fileManager.fileExists(atPath: layout.publicationStagingRootURL.path))
    }

    @Test
    func restoresOnlyValidBackupWhenFinalBundleIsMissing() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let dictionaryID = UUID()
        let backupURL = layout.replacementBackupURL(for: UUID())
        let finalURL = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Recovery Test",
            revision: "1"
        )
        try fileManager.moveItem(at: finalURL, to: backupURL)

        let report = DictionaryLibraryMaintenance(layout: layout)
            .recoverAbandonedReplacements()

        #expect(report.restoredBackups.map(\.path) == [backupURL.path])
        #expect(report.removedStaleBackups.isEmpty)
        #expect(report.conflicts.isEmpty)
        #expect(report.issues.isEmpty)
        #expect(fileManager.fileExists(atPath: finalURL.path))
        #expect(!fileManager.fileExists(atPath: backupURL.path))
        let manifest = try JSONDecoder().decode(
            DictionaryBundleManifest.self,
            from: Data(contentsOf: finalURL.appending(path: "manifest.json"))
        )
        #expect(manifest.dictionaryID == dictionaryID)
        #expect(manifest.revision == "1")

        let repeated = DictionaryLibraryMaintenance(layout: layout)
            .recoverAbandonedReplacements()
        #expect(repeated == DictionaryReplacementRecoveryReport())
    }

    @Test
    func removesStaleBackupWhenPublishedBundleIsValid() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let dictionaryID = UUID()
        let backupURL = layout.replacementBackupURL(for: UUID())
        let originalURL = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Recovery Test",
            revision: "1"
        )
        try fileManager.moveItem(at: originalURL, to: backupURL)
        let finalURL = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Recovery Test",
            revision: "2"
        )

        let report = DictionaryLibraryMaintenance(layout: layout)
            .recoverAbandonedReplacements()

        #expect(report.restoredBackups.isEmpty)
        #expect(report.removedStaleBackups.map(\.path) == [backupURL.path])
        #expect(report.conflicts.isEmpty)
        #expect(report.issues.isEmpty)
        #expect(!fileManager.fileExists(atPath: backupURL.path))
        let manifest = try JSONDecoder().decode(
            DictionaryBundleManifest.self,
            from: Data(contentsOf: finalURL.appending(path: "manifest.json"))
        )
        #expect(manifest.revision == "2")
    }

    @Test
    func preservesBackupWhenFinalBundleConflicts() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let dictionaryID = UUID()
        let backupURL = layout.replacementBackupURL(for: UUID())
        let originalURL = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Original Title",
            revision: "1"
        )
        try fileManager.moveItem(at: originalURL, to: backupURL)
        let finalURL = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Different Title",
            revision: "2"
        )

        let report = DictionaryLibraryMaintenance(layout: layout)
            .recoverAbandonedReplacements()

        #expect(report.conflicts.count == 1)
        #expect(report.conflicts.first?.dictionaryID == dictionaryID)
        #expect(report.conflicts.first?.backupURLs.map(\.path) == [backupURL.path])
        #expect(fileManager.fileExists(atPath: backupURL.path))
        #expect(fileManager.fileExists(atPath: finalURL.path))
    }

    @Test
    func preservesBackupWhenFinalBundleIsInvalid() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let dictionaryID = UUID()
        let backupURL = layout.replacementBackupURL(for: UUID())
        let originalURL = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Recovery Test",
            revision: "1"
        )
        try fileManager.moveItem(at: originalURL, to: backupURL)
        let finalURL = layout.dictionaryBundleURL(for: dictionaryID)
        try fileManager.createDirectory(
            at: finalURL,
            withIntermediateDirectories: true
        )
        try Data("not a manifest".utf8).write(
            to: finalURL.appending(path: "manifest.json")
        )

        let report = DictionaryLibraryMaintenance(layout: layout)
            .recoverAbandonedReplacements()

        #expect(report.conflicts.count == 1)
        #expect(report.conflicts.first?.dictionaryID == dictionaryID)
        #expect(report.conflicts.first?.backupURLs.map(\.path) == [backupURL.path])
        #expect(fileManager.fileExists(atPath: backupURL.path))
        #expect(fileManager.fileExists(atPath: finalURL.path))
    }

    @Test
    func doesNotChooseBetweenMultipleBackups() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let dictionaryID = UUID()
        let firstBackup = layout.replacementBackupURL(for: UUID())
        let secondBackup = layout.replacementBackupURL(for: UUID())
        let firstFinal = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Recovery Test",
            revision: "1"
        )
        try fileManager.moveItem(at: firstFinal, to: firstBackup)
        let secondFinal = try installDictionary(
            layout: layout,
            root: root,
            dictionaryID: dictionaryID,
            title: "Recovery Test",
            revision: "2"
        )
        try fileManager.moveItem(at: secondFinal, to: secondBackup)

        let report = DictionaryLibraryMaintenance(layout: layout)
            .recoverAbandonedReplacements()

        #expect(report.conflicts.count == 1)
        #expect(Set(report.conflicts[0].backupURLs.map(\.path)) == Set([
            firstBackup.path,
            secondBackup.path,
        ]))
        #expect(!fileManager.fileExists(
            atPath: layout.dictionaryBundleURL(for: dictionaryID).path
        ))
        #expect(fileManager.fileExists(atPath: firstBackup.path))
        #expect(fileManager.fileExists(atPath: secondBackup.path))
    }

    @Test
    func preservesMalformedAndSymbolicLinkBackups() throws {
        let fileManager = FileManager.default
        let root = temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let layout = makeLayout(root: root)
        let malformed = layout.replacementBackupURL(for: UUID())
        let link = layout.replacementBackupURL(for: UUID())
        let outside = root.appending(path: "outside", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: malformed, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outside)

        let report = DictionaryLibraryMaintenance(layout: layout)
            .recoverAbandonedReplacements()

        #expect(report.issues.map(\.url.path) == [malformed.path])
        #expect(report.ignoredEntries.map(\.path) == [link.path])
        #expect(fileManager.fileExists(atPath: malformed.path))
        #expect(fileManager.fileExists(atPath: link.path))
        #expect(fileManager.fileExists(atPath: outside.path))
    }
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(
        path: "TsubameCoreTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
}

private func makeLayout(root: URL) -> DictionaryLibraryLayout {
    DictionaryLibraryLayout(locations: TsubameStorageLocations(
        dataRoot: root.appending(path: "Data", directoryHint: .isDirectory),
        cacheRoot: root.appending(path: "Cache", directoryHint: .isDirectory),
        temporaryRoot: root.appending(path: "Work", directoryHint: .isDirectory)
    ))
}

private func installDictionary(
    layout: DictionaryLibraryLayout,
    root: URL,
    dictionaryID: UUID,
    title: String,
    revision: String
) throws -> URL {
    let source = root.appending(
        path: "source-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(
        "{\"title\":\"\(title)\",\"format\":3,\"revision\":\"\(revision)\"}".utf8
    ).write(to: source.appending(path: "index.json"))
    try Data(
        #"[["鳥","とり","","",0,["bird"],1,""]]"#.utf8
    ).write(to: source.appending(path: "term_bank_1.json"))
    let result = try YomitanDictionaryInstaller(layout: layout).install(
        from: DictionaryImportSource(url: source),
        dictionaryID: dictionaryID
    )
    return result.bundleURL
}
