import Foundation

public final class SQLiteDictionaryStore: DictionaryStore {
    private static let maximumLookupKeyCount = 500
    private static let maximumResultCount = 500

    private let connection: SQLiteConnection

    public init(databaseURL: URL) throws {
        guard databaseURL.isFileURL else {
            throw DictionaryStoreError.databaseIsNotLocalFile(databaseURL)
        }

        connection = try SQLiteConnection(url: databaseURL, mode: .readOnly)
        try validateSchemaVersion()
    }

    public func lookup(keys: [String], limit: Int) throws -> [DictionaryEntry] {
        guard limit > 0 else {
            throw DictionaryStoreError.invalidLimit(limit)
        }
        guard limit <= Self.maximumResultCount else {
            throw DictionaryStoreError.resultLimitTooLarge(
                actual: limit,
                maximum: Self.maximumResultCount
            )
        }

        let keys = uniqueLookupKeys(keys)
        guard !keys.isEmpty else {
            return []
        }
        guard keys.count <= Self.maximumLookupKeyCount else {
            throw DictionaryStoreError.tooManyLookupKeys(
                actual: keys.count,
                maximum: Self.maximumLookupKeyCount
            )
        }

        let storedEntries = try loadEntries(matching: keys, limit: limit)
        guard !storedEntries.isEmpty else {
            return []
        }
        let definitionsByEntryID = try loadDefinitions(
            entryIDs: storedEntries.map(\.id)
        )

        return storedEntries.map { entry in
            DictionaryEntry(
                id: entry.id,
                expression: entry.expression,
                reading: entry.reading,
                definitionTags: entry.definitionTags,
                rules: entry.rules,
                score: entry.score,
                sequence: entry.sequence,
                termTags: entry.termTags,
                matches: entry.matches,
                definitions: definitionsByEntryID[entry.id] ?? []
            )
        }
    }
}

private extension SQLiteDictionaryStore {
    struct StoredEntry {
        let id: Int64
        let expression: String
        let reading: String
        let definitionTags: String?
        let rules: String
        let score: Double
        let sequence: Int64
        let termTags: String
        var matches: [DictionaryEntryMatch]
    }

    func validateSchemaVersion() throws {
        let statement = try connection.prepare("PRAGMA user_version")
        defer { statement.finalizeIgnoringErrors() }

        guard try statement.step() == .row else {
            throw DictionaryStoreError.unsupportedSchemaVersion(
                actual: 0,
                expected: DictionaryDatabaseSchema.currentVersion
            )
        }
        let version = statement.integer(at: 0)
        guard version == Int64(DictionaryDatabaseSchema.currentVersion) else {
            throw DictionaryStoreError.unsupportedSchemaVersion(
                actual: version,
                expected: DictionaryDatabaseSchema.currentVersion
            )
        }
        try statement.finalize()
    }

    func uniqueLookupKeys(_ keys: [String]) -> [String] {
        var seenUTF8: Set<Data> = []
        var lookupKeys: [String] = []
        lookupKeys.reserveCapacity(keys.count * 2)
        let normalizer = TextNormalizer()

        for key in keys where !key.isEmpty {
            let normalizedKey = normalizer.normalizedString(key)
            for candidate in [key, normalizedKey]
                where !candidate.isEmpty
                    && seenUTF8.insert(Data(candidate.utf8)).inserted {
                lookupKeys.append(candidate)
            }
        }
        return lookupKeys
    }

    func loadEntries(matching keys: [String], limit: Int) throws -> [StoredEntry] {
        let requestedValues = keys.indices.map { "(?, \($0))" }.joined(separator: ", ")
        let statement = try connection.prepare(
            """
            WITH requested(key, request_order) AS (
                VALUES \(requestedValues)
            ),
            selected(
                entry_id, first_request_order, first_match_rank, bank_order, entry_order
            ) AS (
                SELECT
                    lookup_key.entry_id,
                    MIN(requested.request_order),
                    MIN(CASE lookup_key.key_type WHEN 'expression' THEN 0 ELSE 1 END),
                    term_entry.bank_order,
                    term_entry.entry_order
                FROM requested
                JOIN lookup_key ON lookup_key.key = requested.key
                JOIN term_entry ON term_entry.id = lookup_key.entry_id
                GROUP BY lookup_key.entry_id
                ORDER BY 2, 3, 4, 5, 1
                LIMIT ?
            )
            SELECT
                term_entry.id,
                term_entry.expression,
                term_entry.reading,
                term_entry.definition_tags,
                term_entry.rules,
                term_entry.score,
                term_entry.sequence,
                term_entry.term_tags,
                lookup_key.key,
                lookup_key.key_type
            FROM selected
            JOIN term_entry ON term_entry.id = selected.entry_id
            JOIN lookup_key ON lookup_key.entry_id = selected.entry_id
            JOIN requested ON requested.key = lookup_key.key
            ORDER BY
                selected.first_request_order,
                selected.first_match_rank,
                selected.bank_order,
                selected.entry_order,
                selected.entry_id,
                requested.request_order,
                CASE lookup_key.key_type WHEN 'expression' THEN 0 ELSE 1 END
            """
        )
        defer { statement.finalizeIgnoringErrors() }

        for (offset, key) in keys.enumerated() {
            try statement.bind(key, at: Int32(offset + 1))
        }
        try statement.bind(Int64(limit), at: Int32(keys.count + 1))

        var entries: [StoredEntry] = []
        var entryIndices: [Int64: Int] = [:]
        while try statement.step() == .row {
            guard let expression = statement.string(at: 1),
                  let reading = statement.string(at: 2),
                  let rules = statement.string(at: 4),
                  let termTags = statement.string(at: 7),
                  let matchedKey = statement.string(at: 8),
                  let storedKeyType = statement.string(at: 9) else {
                throw DictionaryStoreError.invalidStoredEntry
            }
            guard let keyType = DictionaryLookupKeyType(rawValue: storedKeyType) else {
                throw DictionaryStoreError.invalidStoredLookupKeyType(storedKeyType)
            }

            let entryID = statement.integer(at: 0)
            let match = DictionaryEntryMatch(key: matchedKey, keyType: keyType)
            if let index = entryIndices[entryID] {
                entries[index].matches.append(match)
            } else {
                entryIndices[entryID] = entries.count
                entries.append(
                    StoredEntry(
                        id: entryID,
                        expression: expression,
                        reading: reading,
                        definitionTags: statement.string(at: 3),
                        rules: rules,
                        score: statement.double(at: 5),
                        sequence: statement.integer(at: 6),
                        termTags: termTags,
                        matches: [match]
                    )
                )
            }
        }
        try statement.finalize()
        return entries
    }

    func loadDefinitions(entryIDs: [Int64]) throws -> [Int64: [DictionaryDefinition]] {
        let placeholders = Array(repeating: "?", count: entryIDs.count).joined(separator: ", ")
        let statement = try connection.prepare(
            """
            SELECT entry_id, position, kind, text, content_json
            FROM term_definition
            WHERE entry_id IN (\(placeholders))
            ORDER BY entry_id, position
            """
        )
        defer { statement.finalizeIgnoringErrors() }

        for (offset, entryID) in entryIDs.enumerated() {
            try statement.bind(entryID, at: Int32(offset + 1))
        }

        var definitionsByEntryID: [Int64: [DictionaryDefinition]] = [:]
        while try statement.step() == .row {
            guard let kind = statement.string(at: 2),
                  let contentJSON = statement.data(at: 4) else {
                throw DictionaryStoreError.invalidStoredDefinition
            }
            let entryID = statement.integer(at: 0)
            let position = statement.integer(at: 1)
            guard let position = Int(exactly: position) else {
                throw DictionaryStoreError.invalidStoredDefinition
            }
            definitionsByEntryID[entryID, default: []].append(
                DictionaryDefinition(
                    position: position,
                    kind: kind,
                    text: statement.string(at: 3),
                    contentJSON: contentJSON
                )
            )
        }
        try statement.finalize()
        return definitionsByEntryID
    }
}
