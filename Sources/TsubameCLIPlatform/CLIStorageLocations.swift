import Foundation
import TsubameCore

public enum CLIStorageLocations {
    public static func platformDefault(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TsubameStorageLocations {
        let roots = platformRoots(fileManager: fileManager, environment: environment)
        return TsubameStorageLocations(
            dataRoot: roots.data.appending(path: "Tsubame", directoryHint: .isDirectory),
            cacheRoot: roots.cache.appending(path: "Tsubame", directoryHint: .isDirectory),
            temporaryRoot: fileManager.temporaryDirectory
        )
    }

    private static func platformRoots(
        fileManager: FileManager,
        environment: [String: String]
    ) -> (data: URL, cache: URL) {
        #if os(macOS)
        let home = fileManager.homeDirectoryForCurrentUser
        return (
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? home
                    .appending(path: "Library", directoryHint: .isDirectory)
                    .appending(path: "Application Support", directoryHint: .isDirectory),
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? home
                    .appending(path: "Library", directoryHint: .isDirectory)
                    .appending(path: "Caches", directoryHint: .isDirectory)
        )
        #elseif os(Windows)
        let localAppData = environmentURL("LOCALAPPDATA", environment: environment)
            ?? environmentURL("APPDATA", environment: environment)
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "AppData", directoryHint: .isDirectory)
                .appending(path: "Local", directoryHint: .isDirectory)
        return (
            localAppData,
            localAppData.appending(path: "Cache", directoryHint: .isDirectory)
        )
        #elseif os(Linux)
        let home = fileManager.homeDirectoryForCurrentUser
        let data = environmentURL("XDG_DATA_HOME", environment: environment)
            ?? home
                .appending(path: ".local", directoryHint: .isDirectory)
                .appending(path: "share", directoryHint: .isDirectory)
        let cache = environmentURL("XDG_CACHE_HOME", environment: environment)
            ?? home.appending(path: ".cache", directoryHint: .isDirectory)
        return (data, cache)
        #else
        let home = fileManager.homeDirectoryForCurrentUser
        return (
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? home
                    .appending(path: ".local", directoryHint: .isDirectory)
                    .appending(path: "share", directoryHint: .isDirectory),
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? home.appending(path: ".cache", directoryHint: .isDirectory)
        )
        #endif
    }

    private static func environmentURL(
        _ name: String,
        environment: [String: String]
    ) -> URL? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return URL(filePath: value, directoryHint: .isDirectory)
    }
}
