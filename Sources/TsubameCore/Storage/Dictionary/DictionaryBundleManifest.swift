import Foundation

public struct DictionaryBundleManifest: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public let manifestVersion: Int
    public let dictionaryID: UUID
    public let title: String
    public let revision: String
    public let dictionarySchemaVersion: Int
    public let termCount: Int
    public let termMetadataCount: Int
    public let kanjiCount: Int
    public let kanjiMetadataCount: Int
    public let tagCount: Int
    public let definitionCount: Int
    public let lookupKeyCount: Int
    public let resourceCount: Int
    public let totalResourceBytes: Int64

    public init(
        dictionaryID: UUID,
        title: String,
        revision: String,
        dictionarySchemaVersion: Int,
        termCount: Int,
        termMetadataCount: Int,
        kanjiCount: Int,
        kanjiMetadataCount: Int,
        tagCount: Int,
        definitionCount: Int,
        lookupKeyCount: Int,
        resourceCount: Int,
        totalResourceBytes: Int64
    ) {
        manifestVersion = Self.currentVersion
        self.dictionaryID = dictionaryID
        self.title = title
        self.revision = revision
        self.dictionarySchemaVersion = dictionarySchemaVersion
        self.termCount = termCount
        self.termMetadataCount = termMetadataCount
        self.kanjiCount = kanjiCount
        self.kanjiMetadataCount = kanjiMetadataCount
        self.tagCount = tagCount
        self.definitionCount = definitionCount
        self.lookupKeyCount = lookupKeyCount
        self.resourceCount = resourceCount
        self.totalResourceBytes = totalResourceBytes
    }
}
