import Foundation
import Testing
@testable import TsubameCLIPlatform

@Suite
struct CLIStorageLocationsTests {
    @Test func resolvesPlatformDataAndCacheRoots() {
        let fileManager = FileManager.default

        #if os(macOS)
        let locations = CLIStorageLocations.platformDefault(fileManager: fileManager)
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        #expect(locations.dataRoot.path == applicationSupport.appending(path: "Tsubame").path)
        #expect(locations.cacheRoot.path == caches.appending(path: "Tsubame").path)
        #elseif os(Linux)
        let locations = CLIStorageLocations.platformDefault(
            fileManager: fileManager,
            environment: [
                "XDG_DATA_HOME": "/tmp/tsubame-xdg-data",
                "XDG_CACHE_HOME": "/tmp/tsubame-xdg-cache"
            ]
        )
        #expect(locations.dataRoot.path == "/tmp/tsubame-xdg-data/Tsubame")
        #expect(locations.cacheRoot.path == "/tmp/tsubame-xdg-cache/Tsubame")
        #elseif os(Windows)
        let locations = CLIStorageLocations.platformDefault(
            fileManager: fileManager,
            environment: ["LOCALAPPDATA": #"C:\Users\runner\AppData\Local"#]
        )
        let localAppData = URL(
            filePath: #"C:\Users\runner\AppData\Local"#,
            directoryHint: .isDirectory
        )
        #expect(
            locations.dataRoot.path
                == localAppData.appending(path: "Tsubame", directoryHint: .isDirectory).path
        )
        #expect(
            locations.cacheRoot.path
                == localAppData
                    .appending(path: "Cache", directoryHint: .isDirectory)
                    .appending(path: "Tsubame", directoryHint: .isDirectory)
                    .path
        )
        #endif
    }

    @Test func usesProcessTemporaryDirectory() {
        let fileManager = FileManager.default
        let locations = CLIStorageLocations.platformDefault(fileManager: fileManager)
        #expect(locations.temporaryRoot == fileManager.temporaryDirectory)
    }
}
