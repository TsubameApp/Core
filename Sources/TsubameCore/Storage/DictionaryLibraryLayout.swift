import Foundation

/// Platform-independent layout of Tsubame's durable dictionary library.
///
/// This type only computes URLs. Directory creation and lifecycle operations
/// belong to the importer and dictionary-library implementations.
public struct DictionaryLibraryLayout: Sendable, Equatable {
    public let locations: TsubameStorageLocations

    public init(locations: TsubameStorageLocations) {
        self.locations = locations
    }

    public var applicationDatabaseURL: URL {
        locations.dataRoot.appending(path: "application.sqlite")
    }

    public var dictionariesRootURL: URL {
        locations.dataRoot.appending(path: "Dictionaries", directoryHint: .isDirectory)
    }

    public var publicationStagingRootURL: URL {
        dictionariesRootURL.appending(path: ".staging", directoryHint: .isDirectory)
    }

    public func publicationStagingURL(for importID: UUID) -> URL {
        publicationStagingRootURL.appending(
            path: identifierComponent(importID),
            directoryHint: .isDirectory
        )
    }

    public func temporaryWorkingURL(for importID: UUID) -> URL {
        locations.temporaryRoot
            .appending(path: "Tsubame", directoryHint: .isDirectory)
            .appending(path: identifierComponent(importID), directoryHint: .isDirectory)
    }

    public func dictionaryBundleURL(for dictionaryID: UUID) -> URL {
        dictionariesRootURL.appending(
            path: identifierComponent(dictionaryID),
            directoryHint: .isDirectory
        )
    }

    public func dictionaryDatabaseURL(for dictionaryID: UUID) -> URL {
        dictionaryBundleURL(for: dictionaryID).appending(path: "dictionary.sqlite")
    }

    public func dictionaryManifestURL(for dictionaryID: UUID) -> URL {
        dictionaryBundleURL(for: dictionaryID).appending(path: "manifest.json")
    }

    public func resourcesRootURL(for dictionaryID: UUID) -> URL {
        dictionaryBundleURL(for: dictionaryID).appending(
            path: "resources",
            directoryHint: .isDirectory
        )
    }

    public func resourceURL(
        for resourcePath: DictionaryResourcePath,
        dictionaryID: UUID
    ) -> URL {
        resourcePath.components.reduce(resourcesRootURL(for: dictionaryID)) { url, component in
            url.appending(path: component)
        }
    }

    private func identifierComponent(_ identifier: UUID) -> String {
        identifier.uuidString.lowercased()
    }
}
