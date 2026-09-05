import Foundation

public extension SQLiteDictionaryStore {
    /// Exact ordered payloads for conservative presentation grouping, independent
    /// of the primary lookup policy. Does not fetch metadata or decode JSON.
    func loadDefinitionPayloads(entryID: Int64) throws -> [Data] {
        let query = try connection.prepare("SELECT content_json FROM term_definition WHERE entry_id = ? ORDER BY position")
        defer { query.finalizeIgnoringErrors() }
        try query.bind(entryID, at: 1)
        var result: [Data] = []
        var bytes = 0
        while try query.step() == .row {
            try Task.checkCancellation()
            guard let data = query.data(at: 0) else { throw DictionaryStoreError.invalidStoredDefinition }
            bytes += data.count
            guard bytes <= 8 * 1_024 * 1_024, result.count < 512 else { throw GlossaryDecodingError.limitExceeded }
            result.append(data)
        }
        return result
    }

    func loadEntryDetails(entryID: Int64) throws -> DictionaryEntryDetails {
        let entry = try connection.prepare("SELECT expression, reading, term_tags, definition_tags FROM term_entry WHERE id = ?")
        defer { entry.finalizeIgnoringErrors() }
        try entry.bind(entryID, at: 1)
        guard try entry.step() == .row, let expression = entry.string(at: 0), let reading = entry.string(at: 1) else {
            throw DictionaryStoreError.invalidStoredEntry
        }
        let termNames = (entry.string(at: 2) ?? "").split(separator: " ").map(String.init)
        let definitionNames = (entry.string(at: 3) ?? "").split(separator: " ").map(String.init)
        let definitions = try connection.prepare("SELECT position, content_json FROM term_definition WHERE entry_id = ? ORDER BY position")
        defer { definitions.finalizeIgnoringErrors() }
        try definitions.bind(entryID, at: 1)
        var content: [DictionaryEntryDetails.Definition] = []
        let decoder = DictionaryGlossaryDecoder()
        var byteCount = 0
        while try definitions.step() == .row {
            try Task.checkCancellation()
            guard let data = definitions.data(at: 1) else { throw DictionaryStoreError.invalidStoredDefinition }
            byteCount += data.count
            guard byteCount <= 8 * 1_024 * 1_024, content.count < 512 else { throw GlossaryDecodingError.limitExceeded }
            content.append(.init(position: Int(definitions.integer(at: 0)), nodes: try decoder.decode(data)))
        }
        let metadata = try loadTermMetadata(expression: expression, reading: reading)
        func tags(_ names: [String]) throws -> [DictionaryTag] {
            guard !names.isEmpty else { return [] }
            let unique = Array(Set(names)).sorted().prefix(500)
            let query = try connection.prepare("SELECT name, category, sort_order, notes, score FROM tag WHERE name IN (\(Array(repeating: "?", count: unique.count).joined(separator: ","))) ORDER BY sort_order, bank_order, entry_order")
            defer { query.finalizeIgnoringErrors() }
            for (index, name) in unique.enumerated() { try query.bind(name, at: Int32(index + 1)) }
            var result: [DictionaryTag] = []
            var seen: Set<String> = []
            while try query.step() == .row {
                guard let name = query.string(at: 0), seen.insert(name).inserted else { continue }
                result.append(.init(name: name, category: query.string(at: 1) ?? "", order: query.double(at: 2), notes: query.string(at: 3) ?? "", score: query.double(at: 4)))
            }
            for name in names where seen.insert(name).inserted {
                result.append(.init(name: name, category: "", order: 0, notes: "", score: 0))
            }
            return result
        }
        return DictionaryEntryDetails(definitions: content, metadata: .init(
            termTags: try tags(termNames), definitionTags: try tags(definitionNames),
            frequencies: metadata.frequencies, pitches: metadata.pitches))
    }

    /// Also works for metadata-only dictionaries; clients combine sources in their preferred order.
    func loadTermMetadata(expression: String, reading: String) throws -> DictionaryEntryMetadata {
        let query = try connection.prepare("SELECT mode, data_json FROM term_metadata WHERE term = ? AND mode IN ('freq', 'pitch') ORDER BY bank_order, entry_order LIMIT 500")
        defer { query.finalizeIgnoringErrors() }
        try query.bind(expression, at: 1)
        var frequencies: [DictionaryFrequency] = []
        var pitches: [DictionaryPitchAccent] = []
        while try query.step() == .row {
            try Task.checkCancellation()
            guard let data = query.data(at: 1), data.count <= 1_048_576 else { continue }
            // Unsupported metadata shapes do not hide an otherwise valid definition.
            if query.string(at: 0) == "freq", let frequency = try? DictionaryMetadataDecoder.frequency(data, reading: reading), !frequencies.contains(frequency) {
                frequencies.append(frequency)
            } else if query.string(at: 0) == "pitch", let decoded = try? DictionaryMetadataDecoder.pitches(data, reading: reading) {
                for pitch in decoded where !pitches.contains(pitch) { pitches.append(pitch) }
            }
        }
        return .init(termTags: [], definitionTags: [], frequencies: frequencies, pitches: pitches)
    }
}
