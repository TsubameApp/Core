import CTsubameABITypes
import Foundation

/// Owns stable C allocations; no pointer escapes a temporary Swift string/array.
final class TsubameABIMemory {
    private var blocks: [UnsafeMutableRawPointer] = []
    private var used = 0
    private var capacity = 0
    private var releases: [() -> Void] = []

    deinit {
        for release in releases.reversed() { release() }
        for block in blocks { block.deallocate() }
    }

    /// Diagnostics have separate ownership from result arenas.
    static func copyString(_ value: String) -> TsubameString {
        let bytes = Array(value.utf8)
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
        if bytes.isEmpty {
            pointer.initialize(to: 0)
        } else {
            bytes.withUnsafeBufferPointer {
                pointer.initialize(from: $0.baseAddress!, count: $0.count)
            }
        }
        return TsubameString(data: UnsafePointer(pointer), length: bytes.count)
    }

    func string(_ value: String?) -> TsubameString {
        guard var value else { return TsubameString() }
        return value.withUTF8 { bytes in
            let storage = reserve(byteCount: max(1, bytes.count), alignment: 1)
            let pointer = storage.bindMemory(to: UInt8.self, capacity: max(1, bytes.count))
            if bytes.isEmpty {
                pointer.initialize(to: 0)
            } else {
                pointer.initialize(from: bytes.baseAddress!, count: bytes.count)
            }
            return TsubameString(data: UnsafePointer(pointer), length: bytes.count)
        }
    }

    func array<T>(_ values: [T]) -> UnsafePointer<T>? {
        guard !values.isEmpty else { return nil }
        let count = values.count
        let storage = reserve(
            byteCount: MemoryLayout<T>.stride * count, alignment: MemoryLayout<T>.alignment
        )
        let pointer = storage.bindMemory(to: T.self, capacity: count)
        values.withUnsafeBufferPointer {
            pointer.initialize(from: $0.baseAddress!, count: count)
        }
        releases.append { pointer.deinitialize(count: count) }
        return UnsafePointer(pointer)
    }

    /// Stable chunks avoid an allocator call for every string or nested array.
    private func reserve(byteCount: Int, alignment: Int) -> UnsafeMutableRawPointer {
        if let block = blocks.last {
            let address = Int(bitPattern: block) + used
            let padding = (alignment - address % alignment) % alignment
            if byteCount <= capacity - used - padding {
                let pointer = block.advanced(by: used + padding)
                used += padding + byteCount
                return pointer
            }
        }
        capacity = max(16_384, byteCount)
        let block = UnsafeMutableRawPointer.allocate(
            byteCount: capacity, alignment: max(16, alignment)
        )
        blocks.append(block)
        used = byteCount
        return block
    }
}

final class TsubameABIResult {
    private let memory = TsubameABIMemory()
    private var contents: [TsubameABIContent] = []
    private(set) var view = TsubameResultView()

    init(groups: [LookupResult]) {
        let groups = groups.map { group in
            let entries = group.entries.map(makeEntry)
            return TsubameGroup(
                source_range: TsubameRange(
                    start: group.sourceRange.start, end: group.sourceRange.end
                ),
                entries: memory.array(entries), entry_count: entries.count
            )
        }
        view = TsubameResultView(groups: memory.array(groups), group_count: groups.count)
    }

    private func makeEntry(_ entry: DictionaryEntry) -> TsubameEntry {
        let matches = entry.matches.map {
            TsubameMatch(
                key: memory.string($0.key),
                key_type: UInt32($0.keyType == .expression ? TSUBAME_KEY_EXPRESSION : TSUBAME_KEY_READING)
            )
        }
        let definitions = entry.definitions.map { definition in
            let content = TsubameABIContent(data: definition.contentJSON)
            contents.append(content)
            return TsubameDefinition(
                position: definition.position,
                kind: memory.string(definition.kind),
                text: memory.string(definition.text),
                content: OpaquePointer(Unmanaged.passUnretained(content).toOpaque())
            )
        }
        return TsubameEntry(
            id: entry.id,
            expression: memory.string(entry.expression),
            reading: memory.string(entry.reading),
            definition_tags: memory.string(entry.definitionTags),
            rules: memory.string(entry.rules),
            score: entry.score, sequence: entry.sequence,
            term_tags: memory.string(entry.termTags),
            matches: memory.array(matches), match_count: matches.count,
            definitions: memory.array(definitions), definition_count: definitions.count
        )
    }
}

/// Mutable only behind its lock; published C values never change.
final class TsubameABIContent {
    private let lock = NSLock()
    private var data: Data?
    private var cached: Result<UnsafePointer<TsubameValue>, TsubameABIFailure>?
    private var memory: TsubameABIMemory?

    init(data: Data) { self.data = data }

    func get() throws -> UnsafePointer<TsubameValue> {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return try cached.get() }
        do {
            let decoded = try JSONDecoder().decode(YomitanJSONValue.self, from: data!)
            let memory = TsubameABIMemory()
            let value = try makeValue(decoded, memory: memory, depth: 0)
            let pointer = memory.array([value])!
            self.memory = memory
            cached = .success(pointer)
            data = nil
            return pointer
        } catch {
            let failure = TsubameABIFailure(
                status: Int32(TSUBAME_STATUS_EXECUTION_FAILED),
                code: "invalid_dictionary_content",
                message: "Dictionary definition contains invalid or excessively nested content."
            )
            cached = .failure(failure)
            data = nil
            throw failure
        }
    }

    private func makeValue(
        _ value: YomitanJSONValue, memory: TsubameABIMemory, depth: Int
    ) throws -> TsubameValue {
        guard depth < 256 else {
            throw TsubameABIFailure(
                status: Int32(TSUBAME_STATUS_EXECUTION_FAILED),
                code: "content_too_deep", message: "Structured content is too deeply nested."
            )
        }
        var payload = TsubameValueData()
        let kind: Int
        switch value {
        case .null:
            kind = TSUBAME_VALUE_NULL
        case .boolean(let value):
            kind = TSUBAME_VALUE_BOOLEAN
            payload.boolean_value = value ? 1 : 0
        case .integer(let value):
            kind = TSUBAME_VALUE_INTEGER
            payload.integer_value = Int64(value)
        case .number(let value):
            kind = TSUBAME_VALUE_NUMBER
            payload.number_value = value
        case .string(let value):
            kind = TSUBAME_VALUE_STRING
            payload.string_value = memory.string(value)
        case .array(let values):
            kind = TSUBAME_VALUE_ARRAY
            let children = try values.map { try makeValue($0, memory: memory, depth: depth + 1) }
            payload.array_value = TsubameValueArray(data: memory.array(children), count: children.count)
        case .object(let values):
            kind = TSUBAME_VALUE_OBJECT
            let members = try values.keys.sorted().map { key in
                TsubameMember(
                    key: memory.string(key),
                    value: try makeValue(values[key]!, memory: memory, depth: depth + 1)
                )
            }
            payload.object_value = TsubameMemberArray(data: memory.array(members), count: members.count)
        }
        return TsubameValue(kind: UInt32(kind), value: payload)
    }
}
