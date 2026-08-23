import Foundation

/// Filesystem roots selected by the platform host.
///
/// TsubameCore does not resolve Application Support, AppData, or XDG paths.
/// A macOS, Windows, Linux, CLI, or embedding host supplies those locations.
public struct TsubameStorageLocations: Sendable, Equatable {
    public let dataRoot: URL
    public let cacheRoot: URL
    public let temporaryRoot: URL

    public init(dataRoot: URL, cacheRoot: URL, temporaryRoot: URL) {
        self.dataRoot = dataRoot
        self.cacheRoot = cacheRoot
        self.temporaryRoot = temporaryRoot
    }
}
