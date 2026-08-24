import CTsubameABI
import Foundation
import Testing
@testable import TsubameCore

@Suite(.serialized)
struct TsubameCABITests {
    private var fileManager: FileManager { .default }

    @Test func reportsVersionAndRejectsInvalidPointerLengthPairs() {
        #expect(tsubame_abi_version() == TSUBAME_ABI_VERSION)

        var engine: OpaquePointer?
        var error = TsubameBuffer(data: nil, length: 0)
        let status = tsubame_engine_create(nil, 1, &engine, &error)

        #expect(status == TSUBAME_STATUS_INVALID_ARGUMENT)
        #expect(engine == nil)
        #expect(error.data != nil)
        #expect(error.length > 0)
        tsubame_buffer_free(&error)
        #expect(error.data == nil)
        #expect(error.length == 0)
        tsubame_buffer_free(&error)
    }

    @Test func executesPositionedLookupAndReturnsDeterministicJSON() throws {
        try withEngine { engine in
            let request = #"{"schemaVersion":1,"operation":"positionedLookup","request":{"text":"食べました","position":0,"resultLimit":100}}"#

            let first = try execute(engine: engine, request: Array(request.utf8))
            let second = try execute(engine: engine, request: Array(request.utf8))

            #expect(first == second)
            let json = try #require(
                JSONSerialization.jsonObject(with: first) as? [String: Any]
            )
            #expect(json["schemaVersion"] as? Int == 1)
            #expect(json["operation"] as? String == "positionedLookup")
            let result = try #require(json["result"] as? [String: Any])
            let range = try #require(result["sourceRange"] as? [String: Any])
            #expect(range["start"] as? Int == 0)
            #expect(range["end"] as? Int == 15)
            let entries = try #require(result["entries"] as? [[String: Any]])
            #expect(entries.first?["expression"] as? String == "食べる")
            let definitions = try #require(entries.first?["definitions"] as? [[String: Any]])
            #expect(definitions.first?["content"] as? String == "to eat")
        }
    }

    @Test func executesRangeScanWithAbsoluteOriginalUTF8Ranges() throws {
        try withEngine { engine in
            let request = #"{"schemaVersion":1,"operation":"rangeScan","request":{"text":"前食べましたｶﾞｸｾｲ後","range":{"start":3,"end":33},"resultGroupLimit":100,"entriesPerGroupLimit":100}}"#
            let data = try execute(engine: engine, request: Array(request.utf8))
            let json = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let results = try #require(json["results"] as? [[String: Any]])
            let ranges = results.compactMap { result -> String? in
                guard let range = result["sourceRange"] as? [String: Any],
                      let start = range["start"] as? Int,
                      let end = range["end"] as? Int else { return nil }
                return "\(start)..<\(end)"
            }
            #expect(ranges == ["3..<18", "3..<9", "18..<33"])
            let expressions = results.compactMap {
                ($0["entries"] as? [[String: Any]])?.first?["expression"] as? String
            }
            #expect(expressions == ["食べる", "食べる", "ガクセイ"])
        }
    }

    @Test func distinguishesMalformedUTF8MalformedJSONAndSchemaErrors() throws {
        try withEngine { engine in
            let invalidUTF8: [UInt8] = [0xC3, 0x28]
            let utf8Failure = try executeFailure(engine: engine, request: invalidUTF8)
            #expect(utf8Failure.status == TSUBAME_STATUS_INVALID_UTF8)
            #expect(utf8Failure.error.contains(#""code":"invalid_request_utf8""#))

            let jsonFailure = try executeFailure(engine: engine, request: Array("{".utf8))
            #expect(jsonFailure.status == TSUBAME_STATUS_INVALID_JSON)
            #expect(jsonFailure.error.contains(#""code":"malformed_json""#))

            let unknownField = #"{"schemaVersion":1,"operation":"positionedLookup","request":{"text":"食べました","position":0,"resultLimit":100,"extra":true}}"#
            let schemaFailure = try executeFailure(
                engine: engine,
                request: Array(unknownField.utf8)
            )
            #expect(schemaFailure.status == TSUBAME_STATUS_INVALID_REQUEST)
            #expect(schemaFailure.error.contains("Unknown field"))
        }
    }

    @Test func rejectsUnsupportedSerializationAndOverflowingLengths() throws {
        try withEngine { engine in
            var result = TsubameBuffer(data: nil, length: 0)
            var error = TsubameBuffer(data: nil, length: 0)
            let unsupported = tsubame_engine_execute(
                engine,
                999,
                nil,
                0,
                &result,
                &error
            )
            #expect(unsupported == TSUBAME_STATUS_UNSUPPORTED)
            #expect(result.data == nil)
            #expect(error.data != nil)
            tsubame_buffer_free(&error)

            let overflow = tsubame_engine_execute(
                engine,
                TSUBAME_SERIALIZATION_JSON_V1,
                nil,
                .max,
                &result,
                &error
            )
            #expect(overflow == TSUBAME_STATUS_INVALID_ARGUMENT)
            #expect(result.data == nil)
            #expect(error.data != nil)
            tsubame_buffer_free(&error)
        }
    }

    @Test func strictDecoderRejectsMissingAndUnknownEnvelopeFields() {
        let missing = Data(
            #"{"schemaVersion":1,"operation":"positionedLookup"}"#.utf8
        )
        #expect(throws: TsubameABIError.self) {
            _ = try TsubameABIV1RequestDecoder.decode(missing)
        }

        let unknown = Data(
            #"{"schemaVersion":1,"operation":"positionedLookup","request":{"text":"食べる","position":0,"resultLimit":1},"extra":0}"#.utf8
        )
        #expect(throws: TsubameABIError.self) {
            _ = try TsubameABIV1RequestDecoder.decode(unknown)
        }
    }

    private func withEngine(_ body: (OpaquePointer) throws -> Void) throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            var engine: OpaquePointer?
            var error = TsubameBuffer(data: nil, length: 0)
            let path = Array(database.path.utf8)
            let status = path.withUnsafeBufferPointer {
                tsubame_engine_create($0.baseAddress, $0.count, &engine, &error)
            }
            defer { tsubame_buffer_free(&error) }
            #expect(status == TSUBAME_STATUS_OK)
            let handle = try #require(engine)
            defer { tsubame_engine_destroy(handle) }
            try body(handle)
        }
    }

    private func execute(engine: OpaquePointer, request: [UInt8]) throws -> Data {
        var result = TsubameBuffer(data: nil, length: 0)
        var error = TsubameBuffer(data: nil, length: 0)
        let status = request.withUnsafeBufferPointer {
            tsubame_engine_execute(
                engine,
                TSUBAME_SERIALIZATION_JSON_V1,
                $0.baseAddress,
                $0.count,
                &result,
                &error
            )
        }
        defer {
            tsubame_buffer_free(&result)
            tsubame_buffer_free(&error)
        }
        guard status == TSUBAME_STATUS_OK else {
            throw TestFailure("ABI execute failed with status \(status): \(string(from: error))")
        }
        return data(from: result)
    }

    private func executeFailure(
        engine: OpaquePointer,
        request: [UInt8]
    ) throws -> (status: TsubameStatus, error: String) {
        var result = TsubameBuffer(data: nil, length: 0)
        var error = TsubameBuffer(data: nil, length: 0)
        let status = request.withUnsafeBufferPointer {
            tsubame_engine_execute(
                engine,
                TSUBAME_SERIALIZATION_JSON_V1,
                $0.baseAddress,
                $0.count,
                &result,
                &error
            )
        }
        defer {
            tsubame_buffer_free(&result)
            tsubame_buffer_free(&error)
        }
        #expect(status != TSUBAME_STATUS_OK)
        #expect(result.data == nil)
        return (status, string(from: error))
    }

    private func data(from buffer: TsubameBuffer) -> Data {
        guard let data = buffer.data, let count = Int(exactly: buffer.length) else {
            return Data()
        }
        return Data(bytes: data, count: count)
    }

    private func string(from buffer: TsubameBuffer) -> String {
        String(data: data(from: buffer), encoding: .utf8) ?? ""
    }

    private func makeDictionaryDatabase(in directory: URL) throws -> URL {
        let archive = directory.appending(path: "dictionary.zip")
        let database = directory.appending(path: "dictionary.sqlite")
        try makeZIP([
            .file(
                "index.json",
                #"{"title":"C ABI Test","format":3,"revision":"1"}"#
            ),
            .file(
                "term_bank_1.json",
                #"[["食べる","たべる","v1","v1",10,["to eat"],1,""],["ガクセイ","がくせい","","",5,["student"],2,""]]"#
            ),
        ]).write(to: archive)
        _ = try YomitanSQLiteDictionaryImporter(
            temporaryRoot: directory.appending(path: "temporary")
        ).import(
            from: DictionaryImportSource(url: archive),
            to: database
        )
        return database
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = fileManager.temporaryDirectory.appending(
            path: "TsubameCABITests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try body(directory)
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
