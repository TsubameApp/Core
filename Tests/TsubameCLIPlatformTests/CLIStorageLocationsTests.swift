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
        #expect(locations.dataRoot.path.hasSuffix(#"AppData\Local\Tsubame"#))
        #expect(locations.cacheRoot.path.hasSuffix(#"AppData\Local\Cache\Tsubame"#))
        #endif
    }

    @Test func usesProcessTemporaryDirectory() {
        let fileManager = FileManager.default
        let locations = CLIStorageLocations.platformDefault(fileManager: fileManager)
        #expect(locations.temporaryRoot == fileManager.temporaryDirectory)
    }
}
