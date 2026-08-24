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

    public func lookup(
        keys: [DictionaryLookupKey],
        limit: Int
    ) throws -> [DictionaryEntry] {
        guard limit > 0 else {
            throw DictionaryStoreError.invalidLimit(limit)
        }
        guard limit <= Self.maximumResultCount else {
            throw DictionaryStoreError.resultLimitTooLarge(
                actual: limit,
                maximum: Self.maximumResultCount
            )
        }

        let keys = try uniqueLookupKeys(keys)
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

    struct LookupKeyIdentity: Hashable {
        let bytes: Data
        let requiredRules: UInt16?
    }

    func uniqueLookupKeys(
        _ keys: [DictionaryLookupKey]
    ) throws -> [DictionaryLookupKey] {
        var seen: Set<LookupKeyIdentity> = []
        var prepared: [DictionaryLookupKey] = []
        prepared.reserveCapacity(keys.count)

        for key in keys where !key.key.isEmpty {
            if let requiredRules = key.requiredRules, requiredRules.isEmpty {
                throw DictionaryStoreError.emptyRequiredRules
            }
            let identity = LookupKeyIdentity(
                bytes: Data(key.key.utf8),
                requiredRules: key.requiredRules?.rawValue
            )
            guard seen.insert(identity).inserted else { continue }
            prepared.append(key)
        }
        return prepared
    }

    func loadEntries(
        matching keys: [DictionaryLookupKey],
        limit: Int
    ) throws -> [StoredEntry] {
        let requestedValues = keys.enumerated().map { offset, key in
            let requiresRules = key.requiredRules == nil ? 0 : 1
            let ruleMask = key.requiredRules?.rawValue ?? 0
            return "(?, \(offset), \(requiresRules), \(ruleMask))"
        }.joined(separator: ", ")
        let selectedCompatibility = ruleCompatibilitySQL(
            requestedAlias: "requested",
            entryAlias: "term_entry"
        )
        let matchedCompatibility = ruleCompatibilitySQL(
            requestedAlias: "matched_request",
            entryAlias: "term_entry"
        )
        let statement = try connection.prepare(
            """
            WITH requested(
                key, request_order, requires_rule_match, required_rule_mask
            ) AS (
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
                WHERE \(selectedCompatibility)
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
            WHERE EXISTS (
                SELECT 1
                FROM requested AS matched_request
                WHERE matched_request.key = lookup_key.key
                  AND \(matchedCompatibility)
            )
            ORDER BY
                selected.first_request_order,
                selected.first_match_rank,
                selected.bank_order,
                selected.entry_order,
                selected.entry_id,
                (
                    SELECT MIN(matched_request.request_order)
                    FROM requested AS matched_request
                    WHERE matched_request.key = lookup_key.key
                      AND \(matchedCompatibility)
                ),
                CASE lookup_key.key_type WHEN 'expression' THEN 0 ELSE 1 END
            """
        )
        defer { statement.finalizeIgnoringErrors() }

        for (offset, key) in keys.enumerated() {
            try statement.bind(key.key, at: Int32(offset + 1))
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

    func ruleCompatibilitySQL(requestedAlias: String, entryAlias: String) -> String {
        let rules = "(' ' || \(entryAlias).rules || ' ')"
        return """
        (
            \(requestedAlias).requires_rule_match = 0
            OR (
                ((\(requestedAlias).required_rule_mask & \(DictionaryRuleSet.ichidan.rawValue)) != 0
                    AND \(rules) GLOB '* v1* *')
                OR ((\(requestedAlias).required_rule_mask & \(DictionaryRuleSet.godan.rawValue)) != 0
                    AND \(rules) GLOB '* v5* *')
                OR ((\(requestedAlias).required_rule_mask & \(DictionaryRuleSet.kuru.rawValue)) != 0
                    AND \(rules) GLOB '* vk *')
                OR ((\(requestedAlias).required_rule_mask & \(DictionaryRuleSet.suru.rawValue)) != 0
                    AND (\(rules) GLOB '* vs *' OR \(rules) GLOB '* vs-* *'))
                OR ((\(requestedAlias).required_rule_mask & \(DictionaryRuleSet.zuru.rawValue)) != 0
                    AND \(rules) GLOB '* vz *')
                OR ((\(requestedAlias).required_rule_mask & \(DictionaryRuleSet.iAdjective.rawValue)) != 0
                    AND \(rules) GLOB '* adj-i* *')
            )
        )
        """
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
