import CTsubameABI
import Dispatch
import Foundation
import Testing
@testable import TsubameCore

@Suite(.serialized)
struct TsubameCABITests {
    private var fileManager: FileManager { .default }

    @Test func errorsAreTypedOwnedAndResettable() {
        #expect(tsubame_abi_version() == 1)
        var engine: OpaquePointer?
        var error = TsubameError()
        #expect(tsubame_engine_create(nil, 1, &engine, &error) == TSUBAME_STATUS_INVALID_ARGUMENT)
        #expect(engine == nil)
        #expect(error.status == TSUBAME_STATUS_INVALID_ARGUMENT)
        #expect(string(error.code) == "null_input")
        tsubame_error_free(&error)
        #expect(error.status == 0)
        #expect(error.code.data == nil)
        #expect(error.message.data == nil)
        tsubame_error_free(&error)
        tsubame_error_free(nil)
        tsubame_engine_destroy(nil)
        tsubame_result_destroy(nil)
    }

    @Test func lookupReturnsTypedEntriesAndLazyContent() throws {
        try withEngine { engine in
            let result = try lookup(engine, text: "食べました")
            defer { tsubame_result_destroy(result) }
            let view = try view(result)
            #expect(view.group_count == 1)
            let group = try #require(view.groups).pointee
            #expect(group.source_range.start == 0)
            #expect(group.source_range.end == 15)
            #expect(group.entry_count == 1)
            let entry = try #require(group.entries).pointee
            #expect(string(entry.expression) == "食べる")
            #expect(string(entry.reading) == "たべる")
            #expect(entry.score == 10)
            #expect(entry.sequence == 1)
            #expect(entry.match_count == 1)
            #expect(try #require(entry.matches).pointee.key_type == TSUBAME_KEY_EXPRESSION)
            #expect(string(try #require(entry.matches).pointee.key) == "食べる")
            let definition = try #require(entry.definitions).pointee
            #expect(string(definition.text) == "to eat")
            let content = try content(definition.content)
            #expect(content.pointee.kind == TSUBAME_VALUE_STRING)
            #expect(string(content.pointee.value.string_value) == "to eat")
            #expect(try self.content(definition.content) == content)
        }
    }

    @Test func scanPreservesAbsoluteRangesAndOrder() throws {
        try withEngine { engine in
            var result: OpaquePointer?
            var error = TsubameError()
            let text = Array("前食べましたｶﾞｸｾｲ後".utf8)
            let status = text.withUnsafeBufferPointer {
                tsubame_scan(engine, $0.baseAddress, $0.count, 3, 33, 100, 100, &result, &error)
            }
            defer { tsubame_result_destroy(result); tsubame_error_free(&error) }
            #expect(status == TSUBAME_STATUS_OK)
            let view = try view(try #require(result))
            let groups = UnsafeBufferPointer(start: view.groups, count: view.group_count)
            #expect(groups.map { "\($0.source_range.start)..<\($0.source_range.end)" } ==
                    ["3..<18", "3..<9", "18..<33"])
            #expect(groups.map { string($0.entries!.pointee.expression) } ==
                    ["食べる", "食べる", "ガクセイ"])
        }
    }

    @Test func resultSurvivesInputMutationNextQueryAndEngineDestruction() throws {
        var result: OpaquePointer?
        try withEngine { engine in
            var bytes = Array("食べました".utf8)
            var error = TsubameError()
            let status = bytes.withUnsafeBufferPointer {
                tsubame_lookup(engine, $0.baseAddress, $0.count, 0, 100, &result, &error)
            }
            defer { tsubame_error_free(&error) }
            #expect(status == TSUBAME_STATUS_OK)
            bytes = Array(repeating: 0, count: bytes.count)
            let next = try lookup(engine, text: "ガクセイ")
            tsubame_result_destroy(next)
        }
        let handle = try #require(result)
        defer { tsubame_result_destroy(handle) }
        let entry = try #require(try view(handle).groups?.pointee.entries).pointee
        #expect(string(entry.expression) == "食べる")
        let value = try content(entry.definitions?.pointee.content)
        #expect(string(value.pointee.value.string_value) == "to eat")
    }

    @Test func rejectsInvalidArgumentsUTF8AndCharacterBoundaries() throws {
        try withEngine { engine in
            var result: OpaquePointer?
            var error = TsubameError()
            #expect(tsubame_lookup(engine, nil, .max, 0, 1, &result, &error) ==
                    TSUBAME_STATUS_INVALID_ARGUMENT)
            #expect(string(error.code) == "input_too_large")
            tsubame_error_free(&error)
            #expect(tsubame_lookup(engine, nil, 1, 0, 1, &result, &error) ==
                    TSUBAME_STATUS_INVALID_ARGUMENT)
            tsubame_error_free(&error)
            #expect(tsubame_lookup(engine, nil, 0, 0, 1, &result, &error) ==
                    TSUBAME_STATUS_INVALID_REQUEST)
            tsubame_error_free(&error)
            let bad: [UInt8] = [0xff]
            #expect(bad.withUnsafeBufferPointer {
                tsubame_lookup(engine, $0.baseAddress, $0.count, 0, 1, &result, &error)
            } == TSUBAME_STATUS_INVALID_UTF8)
            tsubame_error_free(&error)
            let bytes = Array("食べました".utf8)
            for (position, limit, expected) in [
                (1, 100, TSUBAME_STATUS_INVALID_REQUEST),
                (0, 0, TSUBAME_STATUS_INVALID_REQUEST),
                (0, 501, TSUBAME_STATUS_INVALID_REQUEST),
                (Int.max, 1, TSUBAME_STATUS_INVALID_REQUEST),
                (-1, 1, TSUBAME_STATUS_INVALID_ARGUMENT)
            ] {
                let status = bytes.withUnsafeBufferPointer {
                    tsubame_lookup(engine, $0.baseAddress, $0.count, position, limit, &result, &error)
                }
                #expect(status == expected)
                #expect(result == nil)
                tsubame_error_free(&error)
            }
            #expect(bytes.withUnsafeBufferPointer {
                tsubame_scan(engine, $0.baseAddress, $0.count, 12, 3, 1, 1, &result, &error)
            } == TSUBAME_STATUS_INVALID_REQUEST)
            tsubame_error_free(&error)
        }
    }

    @Test func nullOutputsDoNotCreateOwnedObjects() throws {
        var error = TsubameError()
        #expect(tsubame_engine_create(nil, 0, nil, &error) == TSUBAME_STATUS_INVALID_ARGUMENT)
        tsubame_error_free(&error)
        try withEngine { engine in
            var result: OpaquePointer?
            #expect(tsubame_lookup(engine, nil, 0, 0, 1, &result, nil) ==
                    TSUBAME_STATUS_INVALID_ARGUMENT)
            #expect(result == nil)
            #expect(tsubame_lookup(engine, nil, 0, 0, 1, nil, &error) ==
                    TSUBAME_STATUS_INVALID_ARGUMENT)
            tsubame_error_free(&error)
        }
        var view = TsubameResultView(groups: nil, group_count: 5)
        #expect(tsubame_result_get_view(nil, &view) == TSUBAME_STATUS_INVALID_ARGUMENT)
        #expect(view.group_count == 0)
        #expect(tsubame_result_get_view(nil, nil) == TSUBAME_STATUS_INVALID_ARGUMENT)
        var value: UnsafePointer<TsubameValue>?
        #expect(tsubame_content_get(nil, &value, &error) == TSUBAME_STATUS_INVALID_ARGUMENT)
        #expect(value == nil)
        tsubame_error_free(&error)
    }

    @Test func structuredContentCoversEveryValueKindAndOptionalStrings() throws {
        let data = Data(#"{"z":null,"a":[true,42,2.5,"",{"x":"日本語"}]}"#.utf8)
        try withSyntheticResult(data: data) { result in
            let entry = try #require(try view(result).groups?.pointee.entries).pointee
            #expect(entry.definition_tags.data == nil)
            #expect(entry.term_tags.data != nil)
            #expect(entry.term_tags.length == 0)
            let definition = try #require(entry.definitions).pointee
            #expect(definition.text.data == nil)
            let root = try content(definition.content).pointee
            #expect(root.kind == TSUBAME_VALUE_OBJECT)
            let members = UnsafeBufferPointer(
                start: root.value.object_value.data, count: root.value.object_value.count
            )
            #expect(members.map { string($0.key) } == ["a", "z"])
            #expect(members[1].value.kind == TSUBAME_VALUE_NULL)
            #expect(members[0].value.kind == TSUBAME_VALUE_ARRAY)
            let array = members[0].value.value.array_value
            let values = UnsafeBufferPointer(start: array.data, count: array.count)
            #expect(values.count == 5)
            #expect(values[0].kind == TSUBAME_VALUE_BOOLEAN)
            #expect(values[0].value.boolean_value == 1)
            #expect(values[1].kind == TSUBAME_VALUE_INTEGER)
            #expect(values[1].value.integer_value == 42)
            #expect(values[2].kind == TSUBAME_VALUE_NUMBER)
            #expect(values[2].value.number_value == 2.5)
            #expect(values[3].kind == TSUBAME_VALUE_STRING)
            #expect(string(values[3].value.string_value) == "")
            #expect(values[3].value.string_value.data != nil)
            let nested = try #require(values[4].value.object_value.data).pointee
            #expect(string(nested.value.value.string_value) == "日本語")
        }
    }

    @Test func malformedContentFailsOnlyOnDemandAndCachesFailure() throws {
        try withSyntheticResult(data: Data("broken".utf8)) { result in
            let entry = try #require(try view(result).groups?.pointee.entries).pointee
            #expect(string(entry.expression) == "test")
            for _ in 0..<2 {
                var value: UnsafePointer<TsubameValue>?
                var error = TsubameError()
                #expect(tsubame_content_get(entry.definitions?.pointee.content, &value, &error) ==
                        TSUBAME_STATUS_EXECUTION_FAILED)
                #expect(value == nil)
                #expect(string(error.code) == "invalid_dictionary_content")
                tsubame_error_free(&error)
            }
        }
    }

    @Test func concurrentQueriesAndContentReads() throws {
        try withEngine { engine in
            let shared = SharedABIHandle(pointer: engine)
            DispatchQueue.concurrentPerform(iterations: 24) { _ in
                var result: OpaquePointer?
                var error = TsubameError()
                let text = Array("食べました".utf8)
                let status = text.withUnsafeBufferPointer {
                    tsubame_lookup(shared.pointer, $0.baseAddress, $0.count, 0, 100, &result, &error)
                }
                #expect(status == TSUBAME_STATUS_OK)
                var view = TsubameResultView()
                #expect(tsubame_result_get_view(result, &view) == TSUBAME_STATUS_OK)
                #expect(view.group_count == 1)
                tsubame_result_destroy(result)
                tsubame_error_free(&error)
            }
        }
        try withSyntheticResult(data: Data(#"{"key":[1,2,3]}"#.utf8)) { result in
            let definition = try #require(try view(result).groups?.pointee.entries?.pointee.definitions)
            let shared = SharedABIHandle(pointer: try #require(definition.pointee.content))
            DispatchQueue.concurrentPerform(iterations: 24) { _ in
                var first: UnsafePointer<TsubameValue>?
                var second: UnsafePointer<TsubameValue>?
                var error = TsubameError()
                #expect(tsubame_content_get(shared.pointer, &first, &error) == TSUBAME_STATUS_OK)
                #expect(tsubame_content_get(shared.pointer, &second, &error) == TSUBAME_STATUS_OK)
                #expect(first == second)
                #expect(first?.pointee.kind == UInt32(TSUBAME_VALUE_OBJECT))
                tsubame_error_free(&error)
            }
        }
    }

    @Test func emptyResultsAndLargeArenaChunksHaveStableViews() throws {
        let empty = TsubameABIResult(groups: [])
        #expect(empty.view.group_count == 0)
        #expect(empty.view.groups == nil)
        let text = String(repeating: "日本語", count: 4_000)
        let entries = (0..<40).map { index in
            DictionaryEntry(
                id: Int64(index), expression: text, reading: "", definitionTags: nil,
                rules: "", score: 0, sequence: 0, termTags: "", matches: [], definitions: []
            )
        }
        let owner = TsubameABIResult(groups: [
            LookupResult(sourceRange: UTF8TextRange(start: 0, end: 3), entries: entries)
        ])
        let group = try #require(owner.view.groups).pointee
        #expect(group.entry_count == 40)
        for entry in UnsafeBufferPointer(start: group.entries, count: group.entry_count) {
            #expect(string(entry.expression) == text)
            #expect(entry.matches == nil)
            #expect(entry.definitions == nil)
        }
        withExtendedLifetime(owner) {}
        try withEngine { engine in
            let result = try lookup(engine, text: "不存在")
            defer { tsubame_result_destroy(result) }
            let group = try #require(try view(result).groups).pointee
            #expect(group.entry_count == 0)
            #expect(group.entries == nil)
        }
    }

    private func string(_ value: TsubameString) -> String? {
        guard let data = value.data else { return nil }
        return String(bytes: UnsafeBufferPointer(start: data, count: value.length), encoding: .utf8)
    }

    private func view(_ result: OpaquePointer) throws -> TsubameResultView {
        var view = TsubameResultView()
        #expect(tsubame_result_get_view(result, &view) == TSUBAME_STATUS_OK)
        return view
    }

    private func content(_ content: OpaquePointer?) throws -> UnsafePointer<TsubameValue> {
        var value: UnsafePointer<TsubameValue>?
        var error = TsubameError()
        defer { tsubame_error_free(&error) }
        #expect(tsubame_content_get(content, &value, &error) == TSUBAME_STATUS_OK)
        return try #require(value)
    }

    private func lookup(_ engine: OpaquePointer, text: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        var error = TsubameError()
        let bytes = Array(text.utf8)
        let status = bytes.withUnsafeBufferPointer {
            tsubame_lookup(engine, $0.baseAddress, $0.count, 0, 100, &result, &error)
        }
        defer { tsubame_error_free(&error) }
        #expect(status == TSUBAME_STATUS_OK)
        return try #require(result)
    }

    private func withEngine(_ body: (OpaquePointer) throws -> Void) throws {
        try withTemporaryDirectory { directory in
            let database = try makeDictionaryDatabase(in: directory)
            var engine: OpaquePointer?
            var error = TsubameError()
            let path = Array(database.path.utf8)
            let status = path.withUnsafeBufferPointer {
                tsubame_engine_create($0.baseAddress, $0.count, &engine, &error)
            }
            defer { tsubame_error_free(&error) }
            #expect(status == TSUBAME_STATUS_OK)
            let handle = try #require(engine)
            defer { tsubame_engine_destroy(handle) }
            try body(handle)
        }
    }

    private func withSyntheticResult(
        data: Data, body: (OpaquePointer) throws -> Void
    ) throws {
        let entry = DictionaryEntry(
            id: 1, expression: "test", reading: "", definitionTags: nil,
            rules: "", score: 1, sequence: 2, termTags: "", matches: [],
            definitions: [
                DictionaryDefinition(position: 0, kind: "structured", text: nil, contentJSON: data)
            ]
        )
        let owner = TsubameABIResult(groups: [
            LookupResult(sourceRange: UTF8TextRange(start: 0, end: 4), entries: [entry])
        ])
        let handle = OpaquePointer(Unmanaged.passRetained(owner).toOpaque())
        defer { tsubame_result_destroy(handle) }
        try body(handle)
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

/// Only used while the parent test keeps the pointed-to owner alive.
private struct SharedABIHandle: @unchecked Sendable {
    let pointer: OpaquePointer
}
