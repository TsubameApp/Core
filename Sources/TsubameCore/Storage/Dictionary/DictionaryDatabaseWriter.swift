import Foundation

enum DictionaryDatabaseSchema {
    static let currentVersion = 1
}

final class DictionaryDatabaseWriter {
    private let connection: SQLiteConnection

    init(url: URL) throws {
        connection = try SQLiteConnection(url: url, mode: .readWriteCreate)
    }

    func build<Result>(
        index: YomitanDictionaryIndex,
        indexData: Data,
        body: (DictionaryDatabaseImportSession) throws -> Result
    ) throws -> Result {
        try connection.execute("PRAGMA foreign_keys = ON")
        let result = try connection.inTransaction {
            try createTables()
            try insertDictionary(index, indexData: indexData)

            let session = try DictionaryDatabaseImportSession(connection: connection)
            let result = try body(session)
            try session.finish()

            try createIndices()
            try connection.execute("PRAGMA user_version = \(DictionaryDatabaseSchema.currentVersion)")
            return result
        }

        try validateIntegrity()
        try connection.close()
        return result
    }

    private func createTables() throws {
        try connection.execute(
            """
            CREATE TABLE dictionary (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                title TEXT NOT NULL,
                format INTEGER NOT NULL,
                revision TEXT NOT NULL,
                sequenced INTEGER,
                author TEXT,
                source_language TEXT,
                target_language TEXT,
                frequency_mode TEXT,
                index_json BLOB NOT NULL
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE term_entry (
                id INTEGER PRIMARY KEY,
                bank_order INTEGER NOT NULL,
                entry_order INTEGER NOT NULL,
                expression TEXT NOT NULL,
                reading TEXT NOT NULL,
                definition_tags TEXT,
                rules TEXT NOT NULL,
                score REAL NOT NULL,
                sequence INTEGER NOT NULL,
                term_tags TEXT NOT NULL
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE term_definition (
                entry_id INTEGER NOT NULL REFERENCES term_entry(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                kind TEXT NOT NULL,
                text TEXT,
                content_json BLOB NOT NULL,
                PRIMARY KEY (entry_id, position)
            ) WITHOUT ROWID
            """
        )
        try connection.execute(
            """
            CREATE TABLE lookup_key (
                key TEXT NOT NULL,
                entry_id INTEGER NOT NULL REFERENCES term_entry(id) ON DELETE CASCADE,
                key_type TEXT NOT NULL CHECK (key_type IN ('expression', 'reading')),
                PRIMARY KEY (key, entry_id, key_type)
            ) WITHOUT ROWID
            """
        )
        try connection.execute(
            """
            CREATE TABLE term_metadata (
                id INTEGER PRIMARY KEY,
                bank_order INTEGER NOT NULL,
                entry_order INTEGER NOT NULL,
                term TEXT NOT NULL,
                mode TEXT NOT NULL,
                data_json BLOB NOT NULL
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE kanji_entry (
                id INTEGER PRIMARY KEY,
                bank_order INTEGER NOT NULL,
                entry_order INTEGER NOT NULL,
                character TEXT NOT NULL,
                onyomi TEXT NOT NULL,
                kunyomi TEXT NOT NULL,
                tags TEXT NOT NULL,
                meanings_json BLOB NOT NULL,
                stats_json BLOB NOT NULL
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE kanji_metadata (
                id INTEGER PRIMARY KEY,
                bank_order INTEGER NOT NULL,
                entry_order INTEGER NOT NULL,
                character TEXT NOT NULL,
                mode TEXT NOT NULL,
                data_json BLOB NOT NULL
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE tag (
                id INTEGER PRIMARY KEY,
                bank_order INTEGER NOT NULL,
                entry_order INTEGER NOT NULL,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                sort_order REAL NOT NULL,
                notes TEXT NOT NULL,
                score REAL NOT NULL
            )
            """
        )
    }

    private func insertDictionary(_ index: YomitanDictionaryIndex, indexData: Data) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO dictionary (
                id, title, format, revision, sequenced, author,
                source_language, target_language, frequency_mode, index_json
            ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { statement.finalizeIgnoringErrors() }

        try statement.bind(index.title, at: 1)
        try statement.bind(Int64(index.format), at: 2)
        try statement.bind(index.revision, at: 3)
        try statement.bindOptional(index.sequenced.map { $0 ? Int64(1) : Int64(0) }, at: 4)
        try statement.bindOptional(index.author, at: 5)
        try statement.bindOptional(index.sourceLanguage, at: 6)
        try statement.bindOptional(index.targetLanguage, at: 7)
        try statement.bindOptional(index.frequencyMode, at: 8)
        try statement.bind(indexData, at: 9)
        guard try statement.step() == .done else {
            preconditionFailure("An INSERT statement returned a row.")
        }
        try statement.finalize()
    }

    private func createIndices() throws {
        try connection.execute("CREATE INDEX term_entry_sequence ON term_entry (sequence)")
        try connection.execute("CREATE INDEX term_metadata_term_mode ON term_metadata (term, mode)")
        try connection.execute("CREATE INDEX kanji_entry_character ON kanji_entry (character)")
        try connection.execute("CREATE INDEX kanji_metadata_character_mode ON kanji_metadata (character, mode)")
        try connection.execute("CREATE INDEX tag_name ON tag (name)")
        try connection.execute("ANALYZE")
    }

    private func validateIntegrity() throws {
        let statement = try connection.prepare("PRAGMA integrity_check")
        defer { statement.finalizeIgnoringErrors() }

        guard try statement.step() == .row else {
            throw DictionaryImportError.databaseIntegrityCheckFailed("no result")
        }
        let result = statement.string(at: 0) ?? "no result"
        guard result == "ok", try statement.step() == .done else {
            throw DictionaryImportError.databaseIntegrityCheckFailed(result)
        }
        try statement.finalize()

        let foreignKeys = try connection.prepare("PRAGMA foreign_key_check")
        defer { foreignKeys.finalizeIgnoringErrors() }
        guard try foreignKeys.step() == .done else {
            throw DictionaryImportError.databaseIntegrityCheckFailed(
                "foreign key violation"
            )
        }
        try foreignKeys.finalize()
    }
}

final class DictionaryDatabaseImportSession {
    private let termEntry: SQLiteStatement
    private let definition: SQLiteStatement
    private let lookupKey: SQLiteStatement
    private let termMetadata: SQLiteStatement
    private let kanjiEntry: SQLiteStatement
    private let kanjiMetadata: SQLiteStatement
    private let tag: SQLiteStatement
    private let encoder: JSONEncoder
    private var nextTermID: Int64 = 1
    private var nextTermMetadataID: Int64 = 1
    private var nextKanjiID: Int64 = 1
    private var nextKanjiMetadataID: Int64 = 1
    private var nextTagID: Int64 = 1
    private(set) var definitionCount = 0
    private(set) var lookupKeyCount = 0
    private var isFinished = false

    init(connection: SQLiteConnection) throws {
        termEntry = try connection.prepare(
            """
            INSERT INTO term_entry (
                id, bank_order, entry_order, expression, reading,
                definition_tags, rules, score, sequence, term_tags
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        definition = try connection.prepare(
            """
            INSERT INTO term_definition (entry_id, position, kind, text, content_json)
            VALUES (?, ?, ?, ?, ?)
            """
        )
        lookupKey = try connection.prepare(
            "INSERT INTO lookup_key (key, entry_id, key_type) VALUES (?, ?, ?)"
        )
        termMetadata = try connection.prepare(
            """
            INSERT INTO term_metadata (id, bank_order, entry_order, term, mode, data_json)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        )
        kanjiEntry = try connection.prepare(
            """
            INSERT INTO kanji_entry (
                id, bank_order, entry_order, character, onyomi, kunyomi,
                tags, meanings_json, stats_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        kanjiMetadata = try connection.prepare(
            """
            INSERT INTO kanji_metadata (
                id, bank_order, entry_order, character, mode, data_json
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
        )
        tag = try connection.prepare(
            """
            INSERT INTO tag (
                id, bank_order, entry_order, name, category, sort_order, notes, score
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    deinit {
        finalizeIgnoringErrors()
    }

    func insertTerms(_ entries: [YomitanTermEntry], bankOrder: Int) throws {
        for (entryOrder, entry) in entries.enumerated() {
            let entryID = nextTermID
            nextTermID += 1

            try termEntry.bind(entryID, at: 1)
            try termEntry.bind(Int64(bankOrder), at: 2)
            try termEntry.bind(Int64(entryOrder), at: 3)
            try termEntry.bind(entry.term, at: 4)
            try termEntry.bind(entry.reading, at: 5)
            try termEntry.bindOptional(entry.definitionTags, at: 6)
            try termEntry.bind(entry.rules, at: 7)
            try termEntry.bind(entry.score, at: 8)
            try termEntry.bind(Int64(entry.sequence), at: 9)
            try termEntry.bind(entry.termTags, at: 10)
            try complete(termEntry)

            for (position, item) in entry.glossary.enumerated() {
                try definition.bind(entryID, at: 1)
                try definition.bind(Int64(position), at: 2)
                try definition.bind(item.kind, at: 3)
                try definition.bindOptional(item.plainText, at: 4)
                try definition.bind(try encoder.encode(item), at: 5)
                try complete(definition)
                definitionCount += 1
            }

            try insertLookupKey(entry.term, entryID: entryID, type: "expression")
            if !entry.reading.isEmpty, entry.reading != entry.term {
                try insertLookupKey(entry.reading, entryID: entryID, type: "reading")
            }
        }
    }

    func insertTermMetadata(_ entries: [YomitanTermMetadata], bankOrder: Int) throws {
        for (entryOrder, entry) in entries.enumerated() {
            try termMetadata.bind(nextTermMetadataID, at: 1)
            nextTermMetadataID += 1
            try termMetadata.bind(Int64(bankOrder), at: 2)
            try termMetadata.bind(Int64(entryOrder), at: 3)
            try termMetadata.bind(entry.term, at: 4)
            try termMetadata.bind(entry.mode, at: 5)
            try termMetadata.bind(try encoder.encode(entry.data), at: 6)
            try complete(termMetadata)
        }
    }

    func insertKanji(_ entries: [YomitanKanjiEntry], bankOrder: Int) throws {
        for (entryOrder, entry) in entries.enumerated() {
            try kanjiEntry.bind(nextKanjiID, at: 1)
            nextKanjiID += 1
            try kanjiEntry.bind(Int64(bankOrder), at: 2)
            try kanjiEntry.bind(Int64(entryOrder), at: 3)
            try kanjiEntry.bind(entry.character, at: 4)
            try kanjiEntry.bind(entry.onyomi, at: 5)
            try kanjiEntry.bind(entry.kunyomi, at: 6)
            try kanjiEntry.bind(entry.tags, at: 7)
            try kanjiEntry.bind(try encoder.encode(entry.meanings), at: 8)
            try kanjiEntry.bind(try encoder.encode(entry.stats), at: 9)
            try complete(kanjiEntry)
        }
    }

    func insertKanjiMetadata(_ entries: [YomitanKanjiMetadata], bankOrder: Int) throws {
        for (entryOrder, entry) in entries.enumerated() {
            try kanjiMetadata.bind(nextKanjiMetadataID, at: 1)
            nextKanjiMetadataID += 1
            try kanjiMetadata.bind(Int64(bankOrder), at: 2)
            try kanjiMetadata.bind(Int64(entryOrder), at: 3)
            try kanjiMetadata.bind(entry.character, at: 4)
            try kanjiMetadata.bind(entry.mode, at: 5)
            try kanjiMetadata.bind(try encoder.encode(entry.data), at: 6)
            try complete(kanjiMetadata)
        }
    }

    func insertTags(_ entries: [YomitanTag], bankOrder: Int) throws {
        for (entryOrder, entry) in entries.enumerated() {
            try tag.bind(nextTagID, at: 1)
            nextTagID += 1
            try tag.bind(Int64(bankOrder), at: 2)
            try tag.bind(Int64(entryOrder), at: 3)
            try tag.bind(entry.name, at: 4)
            try tag.bind(entry.category, at: 5)
            try tag.bind(entry.order, at: 6)
            try tag.bind(entry.notes, at: 7)
            try tag.bind(entry.score, at: 8)
            try complete(tag)
        }
    }

    func finish() throws {
        guard !isFinished else {
            return
        }
        isFinished = true
        try termEntry.finalize()
        try definition.finalize()
        try lookupKey.finalize()
        try termMetadata.finalize()
        try kanjiEntry.finalize()
        try kanjiMetadata.finalize()
        try tag.finalize()
    }

    private func insertLookupKey(_ key: String, entryID: Int64, type: String) throws {
        try lookupKey.bind(key, at: 1)
        try lookupKey.bind(entryID, at: 2)
        try lookupKey.bind(type, at: 3)
        try complete(lookupKey)
        lookupKeyCount += 1
    }

    private func complete(_ statement: SQLiteStatement) throws {
        guard try statement.step() == .done else {
            preconditionFailure("An INSERT statement returned a row.")
        }
        try statement.reset()
    }

    private func finalizeIgnoringErrors() {
        termEntry.finalizeIgnoringErrors()
        definition.finalizeIgnoringErrors()
        lookupKey.finalizeIgnoringErrors()
        termMetadata.finalizeIgnoringErrors()
        kanjiEntry.finalizeIgnoringErrors()
        kanjiMetadata.finalizeIgnoringErrors()
        tag.finalizeIgnoringErrors()
    }
}

private extension SQLiteStatement {
    func bindOptional(_ value: String?, at index: Int32) throws {
        if let value {
            try bind(value, at: index)
        } else {
            try bindNull(at: index)
        }
    }

    func bindOptional(_ value: Int64?, at index: Int32) throws {
        if let value {
            try bind(value, at: index)
        } else {
            try bindNull(at: index)
        }
    }
}

private extension YomitanGlossaryItem {
    var kind: String {
        switch self {
        case .text: "text"
        case .object: "object"
        case .deinflection: "deinflection"
        }
    }

    var plainText: String? {
        guard case .text(let text) = self else {
            return nil
        }
        return text
    }
}
