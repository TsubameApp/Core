import Foundation
import Testing
@testable import TsubameCore

@Suite
struct YomitanArchiveExtractorTests {
    private var fileManager: FileManager { .default }

    @Test func extractsFilesAndUnicodePathsFromLocalArchive() throws {
        try withTemporaryDirectory { directory in
            let archive = directory.appending(path: "dictionary.zip")
            let destination = directory.appending(path: "unpacked")
            let archiveData = makeZIP([
                .directory("images/"),
                .file("index.json", #"{"title":"Test","format":3}"#),
                .file("term_bank_1.json", "[]"),
                .file("empty.txt", ""),
                .file("images/日本.webp", "image bytes")
            ])
            try archiveData.write(to: archive)

            let result = try YomitanArchiveExtractor().extract(
                DictionaryImportSource(url: archive),
                to: destination
            )

            #expect(result == destination)
            #expect(try String(contentsOf: destination.appending(path: "index.json"), encoding: .utf8)
                == #"{"title":"Test","format":3}"#)
            #expect(try String(contentsOf: destination.appending(path: "images/日本.webp"), encoding: .utf8)
                == "image bytes")
            #expect(try Data(contentsOf: destination.appending(path: "empty.txt")).isEmpty)
            #expect(try Data(contentsOf: archive) == archiveData)
        }
    }

    @Test func rejectsPathsWhichCanEscapeOrBehaveDifferentlyAcrossPlatforms() throws {
        let unsafePaths = [
            "../escape.txt",
            "nested/../../escape.txt",
            "/absolute.txt",
            "C:/windows.txt",
            #"nested\windows.txt"#,
            "nested/file:stream",
            "nested//empty.txt",
            "nested/./dot.txt",
            "CON.txt",
            "trailing-dot./file.txt"
        ]

        for path in unsafePaths {
            try withTemporaryDirectory { directory in
                let archive = directory.appending(path: "unsafe.zip")
                let destination = directory.appending(path: "unpacked")
                try makeZIP([.file(path, "bad")]).write(to: archive)

                #expect(throws: DictionaryArchiveExtractionError.self, "Expected rejection for \(path)") {
                    try YomitanArchiveExtractor().extract(
                        DictionaryImportSource(url: archive),
                        to: destination
                    )
                }
                #expect(!fileManager.fileExists(atPath: destination.path))
                #expect(!fileManager.fileExists(atPath: directory.deletingLastPathComponent()
                    .appending(path: "escape.txt").path))
            }
        }
    }

    @Test func extractsDeflatedEntries() throws {
        try withTemporaryDirectory { directory in
            let encodedArchive = "UEsDBBQAAAAIAGkZGF1Ad+5oIwAAACEAAAAKAAAAaW5kZXguanNvbqtWKsksyUlVslJyzs8tKEotLk5NUdJRSssvyk0sUbIyrgUAUEsDBBQAAAgIAGkZGF1fGhE8FwAAADUAAAARAAAAaW1hZ2VzL+Wcp+e4ri50eHRLSU3LSSxJTVFIzs8rSc0rKVZIISwCAFBLAQIUAxQAAAAIAGkZGF1Ad+5oIwAAACEAAAAKAAAAAAAAAAAAAACAAQAAAABpbmRleC5qc29uUEsBAhQDFAAACAgAaRkYXV8aETwXAAAANQAAABEAAAAAAAAAAAAAAIABSwAAAGltYWdlcy/lnKfnuK4udHh0UEsFBgAAAAACAAIAdwAAAJEAAAAAAA=="
            let archive = directory.appending(path: "compressed.zip")
            let destination = directory.appending(path: "unpacked")
            try #require(Data(base64Encoded: encodedArchive)).write(to: archive)

            try YomitanArchiveExtractor().extract(
                DictionaryImportSource(url: archive),
                to: destination
            )

            #expect(
                try String(
                    contentsOf: destination.appending(path: "images/圧縮.txt"),
                    encoding: .utf8
                ) == "deflated contents deflated contents deflated contents"
            )
        }
    }

    @Test func rejectsSymlinksAndCaseInsensitivePathCollisions() throws {
        try withTemporaryDirectory { directory in
            let symlinkArchive = directory.appending(path: "symlink.zip")
            try makeZIP([.symlink("image.png", target: "../outside")]).write(to: symlinkArchive)

            #expect(throws: DictionaryArchiveExtractionError.self) {
                try YomitanArchiveExtractor().extract(
                    DictionaryImportSource(url: symlinkArchive),
                    to: directory.appending(path: "symlink-output")
                )
            }

            let collisionArchive = directory.appending(path: "collision.zip")
            try makeZIP([
                .file("Images/a.png", "one"),
                .file("images/A.png", "two")
            ]).write(to: collisionArchive)

            #expect(throws: DictionaryArchiveExtractionError.self) {
                try YomitanArchiveExtractor().extract(
                    DictionaryImportSource(url: collisionArchive),
                    to: directory.appending(path: "collision-output")
                )
            }
        }
    }

    @Test func enforcesEntryCountAndExpandedSizeLimitsBeforeWriting() throws {
        try withTemporaryDirectory { directory in
            let archive = directory.appending(path: "limits.zip")
            try makeZIP([
                .file("one.txt", "12"),
                .file("two.txt", "34")
            ]).write(to: archive)

            let limits = [
                DictionaryArchiveExtractionLimits(maximumEntryCount: 1),
                DictionaryArchiveExtractionLimits(maximumEntryUncompressedBytes: 1),
                DictionaryArchiveExtractionLimits(maximumTotalUncompressedBytes: 3)
            ]

            for (index, limit) in limits.enumerated() {
                let destination = directory.appending(path: "output-\(index)")
                #expect(throws: DictionaryArchiveExtractionError.self) {
                    try YomitanArchiveExtractor(limits: limit).extract(
                        DictionaryImportSource(url: archive),
                        to: destination
                    )
                }
                #expect(!fileManager.fileExists(atPath: destination.path))
            }
        }
    }

    @Test func rejectsCorruptArchiveWithoutLeavingPartialOutput() throws {
        try withTemporaryDirectory { directory in
            let archive = directory.appending(path: "corrupt.zip")
            let destination = directory.appending(path: "unpacked")
            let fileName = "payload.txt"
            var corruptArchive = makeZIP([.file(fileName, "original payload")])
            let firstFileDataOffset = 30 + fileName.utf8.count
            corruptArchive[firstFileDataOffset] ^= 0xff
            try corruptArchive.write(to: archive)

            #expect(throws: DictionaryArchiveExtractionError.self) {
                try YomitanArchiveExtractor().extract(
                    DictionaryImportSource(url: archive),
                    to: destination
                )
            }
            #expect(!fileManager.fileExists(atPath: destination.path))
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory
            .appending(path: "TsubameArchiveTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try body(directory)
    }
}

struct ZIPTestEntry {
    enum Kind {
        case file
        case directory
        case symlink
    }

    let name: String
    let contents: Data
    let kind: Kind

    static func file(_ name: String, _ contents: String) -> Self {
        Self(name: name, contents: Data(contents.utf8), kind: .file)
    }

    static func directory(_ name: String) -> Self {
        Self(name: name, contents: Data(), kind: .directory)
    }

    static func symlink(_ name: String, target: String) -> Self {
        Self(name: name, contents: Data(target.utf8), kind: .symlink)
    }
}

func makeZIP(_ entries: [ZIPTestEntry]) -> Data {
    struct CentralEntry {
        let entry: ZIPTestEntry
        let name: Data
        let crc32: UInt32
        let localOffset: UInt32
    }

    var archive = Data()
    var centralEntries: [CentralEntry] = []

    for entry in entries {
        let name = Data(entry.name.utf8)
        let crc = crc32(entry.contents)
        let offset = UInt32(archive.count)

        archive.appendLittleEndian(UInt32(0x04034b50))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(UInt16(0x0800))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(crc)
        archive.appendLittleEndian(UInt32(entry.contents.count))
        archive.appendLittleEndian(UInt32(entry.contents.count))
        archive.appendLittleEndian(UInt16(name.count))
        archive.appendLittleEndian(UInt16(0))
        archive.append(name)
        archive.append(entry.contents)

        centralEntries.append(CentralEntry(
            entry: entry,
            name: name,
            crc32: crc,
            localOffset: offset
        ))
    }

    let centralOffset = UInt32(archive.count)
    for central in centralEntries {
        let unixMode: UInt32 = switch central.entry.kind {
        case .file: 0o100644
        case .directory: 0o040755
        case .symlink: 0o120777
        }

        archive.appendLittleEndian(UInt32(0x02014b50))
        archive.appendLittleEndian(UInt16(0x0314))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(UInt16(0x0800))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(central.crc32)
        archive.appendLittleEndian(UInt32(central.entry.contents.count))
        archive.appendLittleEndian(UInt32(central.entry.contents.count))
        archive.appendLittleEndian(UInt16(central.name.count))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(unixMode << 16)
        archive.appendLittleEndian(central.localOffset)
        archive.append(central.name)
    }

    let centralSize = UInt32(archive.count) - centralOffset
    archive.appendLittleEndian(UInt32(0x06054b50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(centralSize)
    archive.appendLittleEndian(centralOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}

private func crc32(_ data: Data) -> UInt32 {
    var crc = UInt32.max
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1)))
        }
    }
    return ~crc
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
