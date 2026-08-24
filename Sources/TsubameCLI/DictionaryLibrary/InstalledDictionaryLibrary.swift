import Foundation
import TsubameCore

struct InstalledDictionary {
    let manifest: DictionaryBundleManifest
    let databaseURL: URL
}

enum InstalledDictionaryLibrary {
    static func load(
        layout: DictionaryLibraryLayout,
        fileManager: FileManager = .default
    ) throws -> [InstalledDictionary] {
        let root = layout.dictionariesRootURL
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var dictionaries: [InstalledDictionary] = []
        for bundleURL in children {
            let values = try bundleURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  let directoryID = UUID(uuidString: bundleURL.lastPathComponent) else {
                continue
            }

            let manifestURL = bundleURL.appending(path: "manifest.json")
            let databaseURL = bundleURL.appending(path: "dictionary.sqlite")
            guard fileManager.fileExists(atPath: manifestURL.path),
                  fileManager.fileExists(atPath: databaseURL.path) else {
                throw InstalledDictionaryLibraryError.incompleteBundle(bundleURL)
            }

            let manifest: DictionaryBundleManifest
            do {
                manifest = try JSONDecoder().decode(
                    DictionaryBundleManifest.self,
                    from: Data(contentsOf: manifestURL)
                )
            } catch {
                throw InstalledDictionaryLibraryError.invalidManifest(
                    manifestURL,
                    reason: error.localizedDescription
                )
            }
            guard manifest.manifestVersion == DictionaryBundleManifest.currentVersion else {
                throw InstalledDictionaryLibraryError.unsupportedManifestVersion(
                    actual: manifest.manifestVersion,
                    expected: DictionaryBundleManifest.currentVersion,
                    manifestURL: manifestURL
                )
            }
            guard manifest.dictionaryID == directoryID else {
                throw InstalledDictionaryLibraryError.dictionaryIDMismatch(
                    directoryID: directoryID,
                    manifestID: manifest.dictionaryID,
                    bundleURL: bundleURL
                )
            }
            dictionaries.append(
                InstalledDictionary(manifest: manifest, databaseURL: databaseURL)
            )
        }

        return dictionaries.sorted {
            $0.manifest.dictionaryID.uuidString < $1.manifest.dictionaryID.uuidString
        }
    }
}

private enum InstalledDictionaryLibraryError: LocalizedError {
    case incompleteBundle(URL)
    case invalidManifest(URL, reason: String)
    case unsupportedManifestVersion(actual: Int, expected: Int, manifestURL: URL)
    case dictionaryIDMismatch(directoryID: UUID, manifestID: UUID, bundleURL: URL)

    var errorDescription: String? {
        switch self {
        case .incompleteBundle(let url):
            "Dictionary bundle is incomplete: \(url.path)"
        case .invalidManifest(let url, let reason):
            "Dictionary manifest is invalid at \(url.path): \(reason)"
        case let .unsupportedManifestVersion(actual, expected, url):
            "Dictionary manifest version \(actual) is unsupported; expected \(expected): \(url.path)"
        case let .dictionaryIDMismatch(directoryID, manifestID, url):
            "Dictionary bundle ID \(directoryID) does not match manifest ID \(manifestID): \(url.path)"
        }
    }
}
