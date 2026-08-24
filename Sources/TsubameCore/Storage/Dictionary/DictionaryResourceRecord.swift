import Foundation

public struct DictionaryResourceRecord: Sendable, Equatable, Codable {
    public let logicalPath: DictionaryResourcePath
    public let storedRelativePath: String
    public let mediaType: String
    public let byteSize: Int64

    public init(
        logicalPath: DictionaryResourcePath,
        storedRelativePath: String,
        mediaType: String,
        byteSize: Int64
    ) {
        self.logicalPath = logicalPath
        self.storedRelativePath = storedRelativePath
        self.mediaType = mediaType
        self.byteSize = byteSize
    }
}
