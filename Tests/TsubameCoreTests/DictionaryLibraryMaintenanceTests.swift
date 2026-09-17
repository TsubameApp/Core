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
