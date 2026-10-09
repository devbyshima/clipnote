import Foundation
import NaturalLanguage

/// One place a search was found: which note, what kind of passage, where in
/// the video, and a snippet with the matched words marked.
nonisolated struct SearchHit: Sendable, Equatable {
    let noteID: UUID
    let kind: NoteSnapshot.Passage.Kind
    let start: Double?
    let heading: String
    /// The passage around the match; matched words sit between
    /// `SearchHit.markStart` and `SearchHit.markEnd`.
    let snippet: String
    /// Lower is better.
    let rank: Double

    static let markStart: Character = "\u{1}"
    static let markEnd: Character = "\u{2}"

    /// The snippet without its marks.
    var plainSnippet: String { snippet.filter { $0 != Self.markStart && $0 != Self.markEnd } }
}

/// A note that matched: its best passage and how many passages matched.
nonisolated struct NoteMatch: Sendable, Equatable {
    let noteID: UUID
    let best: SearchHit
    let count: Int
}

/// Every note's text, cut into passages and kept in a full-text index (SQLite
/// FTS5) with an on-device sentence embedding per passage, for finding notes
/// by words or by meaning. It lives in Caches: it can always be rebuilt from
/// the notes, so macOS may clear it and Ovyl rebuilds it.
actor SearchIndex {
    static let shared = SearchIndex(url: SearchIndex.defaultURL)

    nonisolated static var defaultURL: URL {
        URL.cachesDirectory.appending(path: "Index", directoryHint: .isDirectory).appending(path: "library.sqlite")
    }

    /// Bump when the tables or passages change, to rebuild from scratch.
    private static let version = 1

    private let url: URL
    private var database: SQLiteDatabase?
    private var vectors: [Int: [Float]]?
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    init(url: URL) {
        self.url = url
    }

    // MARK: Writing

    /// Replaces everything indexed for the note.
    func update(_ note: NoteSnapshot) {
        guard let db = open() else { return }
        let id = note.id.uuidString
        let passages = note.passages
        try? db.transaction {
            try removeRows(of: id, in: db)
            for passage in passages {
                try db.execute(
                    "INSERT INTO passages (note, kind, start, heading, text) VALUES (?, ?, ?, ?, ?)",
                    [.text(id), .text(passage.kind.rawValue), passage.start.map { .double($0) } ?? .null, .text(passage.heading), .text(passage.text)]
                )
                if let vector = vector(for: passage) {
                    let row = try db.query("SELECT last_insert_rowid()") { $0.int(0) }.first ?? 0
                    try db.execute("INSERT INTO vectors (passage, note, vector) VALUES (?, ?, ?)", [.int(row), .text(id), .blob(Self.data(vector))])
                }
            }
            try db.execute("INSERT OR REPLACE INTO notes (id, fingerprint) VALUES (?, ?)", [.text(id), .text(note.fingerprint)])
        }
        vectors = nil
    }

    func remove(_ noteID: UUID) {
        guard let db = open() else { return }
        try? db.transaction { try removeRows(of: noteID.uuidString, in: db) }
        vectors = nil
    }

    /// Drops notes that are gone and says which notes need indexing again,
    /// given each note's current fingerprint.
    func reconcile(_ fingerprints: [UUID: String]) -> [UUID] {
        guard let db = open() else { return Array(fingerprints.keys) }
        let indexed = (try? db.query("SELECT id, fingerprint FROM notes") { ($0.text(0), $0.text(1)) }) ?? []
        var known: [String: String] = [:]
        for (id, fingerprint) in indexed { known[id] = fingerprint }
        let current = Set(fingerprints.keys.map(\.uuidString))
        try? db.transaction {
            for id in known.keys where !current.contains(id) { try removeRows(of: id, in: db) }
        }
        vectors = nil
        return fingerprints.filter { known[$0.key.uuidString] != $0.value }.map(\.key)
    }

    /// Empties the index; the notes are indexed again as they're reconciled.
    func clear() {
        database = nil
        vectors = nil
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
        }
    }

    private func removeRows(of id: String, in db: SQLiteDatabase) throws {
        try db.execute("DELETE FROM passages WHERE note = ?", [.text(id)])
        try db.execute("DELETE FROM vectors WHERE note = ?", [.text(id)])
        try db.execute("DELETE FROM notes WHERE id = ?", [.text(id)])
    }

    // MARK: Reading

    /// Notes whose words match, best first, each with its best passage.
    func search(_ query: String, in noteIDs: Set<UUID>? = nil, limit: Int = 200) -> [NoteMatch] {
        group(hits(query, limit: limit * 4), in: noteIDs, limit: limit)
    }

    /// Passages that match by words, by meaning, or both, best first: the
    /// two rankings are merged so a passage high in either comes out near
    /// the top.
    func find(_ query: String, limit: Int = 12) -> [SearchHit] {
        let words = hits(query, limit: 40)
        let meaning = related(to: query, limit: 40)
        var scores: [String: (hit: SearchHit, score: Double)] = [:]
        for (list, weight) in [(words, 1.0), (meaning, 0.8)] {
            for (position, hit) in list.enumerated() {
                let key = "\(hit.noteID)|\(hit.kind.rawValue)|\(hit.start ?? -1)|\(hit.heading)|\(hit.plainSnippet.prefix(40))"
                let score = weight / Double(60 + position)
                if let existing = scores[key] {
                    // Keep the marked snippet from the word search.
                    let keep = existing.hit.snippet.contains(SearchHit.markStart) ? existing.hit : hit
                    scores[key] = (keep, existing.score + score)
                } else {
                    scores[key] = (hit, score)
                }
            }
        }
        return scores.values.sorted { $0.score > $1.score }.prefix(limit).map(\.hit)
    }

    /// Matching passages by words, best first.
    func hits(_ query: String, limit: Int) -> [SearchHit] {
        guard let match = Self.matchExpression(query), let db = open() else { return [] }
        let sql = """
            SELECT note, kind, start, heading, snippet(passages, 4, char(1), char(2), '…', 14), bm25(passages, 0, 0, 0, 4.0, 1.0), typeof(start)
            FROM passages WHERE passages MATCH ? ORDER BY bm25(passages, 0, 0, 0, 4.0, 1.0) LIMIT ?
            """
        let rows = (try? db.query(sql, [.text(match), .int(limit)]) { row in
            (row.text(0), row.text(1), row.text(6) == "null" ? nil : row.double(2), row.text(3), row.text(4), row.double(5))
        }) ?? []
        return rows.compactMap { note, kind, start, heading, snippet, rank in
            guard let id = UUID(uuidString: note), let kind = NoteSnapshot.Passage.Kind(rawValue: kind) else { return nil }
            // A match in the title counts for more.
            let boosted = kind == .title ? rank * 2 : rank
            let text = kind == .title && !snippet.contains(SearchHit.markStart) ? heading : snippet
            return SearchHit(noteID: id, kind: kind, start: start, heading: heading, snippet: text, rank: boosted)
        }
        .sorted { $0.rank < $1.rank }
    }

    /// Passages closest in meaning to `text`.
    func related(to text: String, limit: Int) -> [SearchHit] {
        guard let embedding, let query = embedding.vector(for: text).map({ $0.map(Float.init) }), let db = open() else { return [] }
        let all = loadVectors(db)
        let scored = all.map { row, vector in (row, Self.cosine(query, vector)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
        return scored.compactMap { row, score in
            let found = try? db.query("SELECT note, kind, start, heading, text, typeof(start) FROM passages WHERE rowid = ?", [.int(row)]) { row in
                (row.text(0), row.text(1), row.text(5) == "null" ? nil : row.double(2), row.text(3), row.text(4))
            }
            guard let (note, kind, start, heading, text) = found?.first,
                  let id = UUID(uuidString: note), let kind = NoteSnapshot.Passage.Kind(rawValue: kind) else { return nil }
            let snippet = text.count > 220 ? String(text.prefix(220)) + "…" : text
            return SearchHit(noteID: id, kind: kind, start: start, heading: heading, snippet: snippet, rank: Double(1 - score))
        }
    }

    /// Every passage of a note, in order, for reading it piece by piece.
    func passages(of noteID: UUID) -> [SearchHit] {
        guard let db = open() else { return [] }
        let rows = (try? db.query("SELECT kind, start, heading, text, typeof(start) FROM passages WHERE note = ? ORDER BY rowid", [.text(noteID.uuidString)]) { row in
            (row.text(0), row.text(4) == "null" ? nil : row.double(1), row.text(2), row.text(3))
        }) ?? []
        return rows.compactMap { kind, start, heading, text in
            NoteSnapshot.Passage.Kind(rawValue: kind).map { SearchHit(noteID: noteID, kind: $0, start: start, heading: heading, snippet: text, rank: 0) }
        }
    }

    private func group(_ hits: [SearchHit], in noteIDs: Set<UUID>?, limit: Int) -> [NoteMatch] {
        var order: [UUID] = []
        var best: [UUID: SearchHit] = [:]
        var counts: [UUID: Int] = [:]
        for hit in hits {
            if let noteIDs, !noteIDs.contains(hit.noteID) { continue }
            counts[hit.noteID, default: 0] += 1
            if best[hit.noteID] == nil {
                best[hit.noteID] = hit
                order.append(hit.noteID)
            } else if best[hit.noteID]?.kind == .title, hit.kind != .title {
                // Prefer showing where in the note it was found.
                best[hit.noteID] = hit
            }
        }
        return order.prefix(limit).compactMap { id in best[id].map { NoteMatch(noteID: id, best: $0, count: counts[id] ?? 1) } }
    }

    // MARK: Query

    /// The search as an FTS5 query: every word must appear, and the words
    /// match as prefixes, so results show while a word is still being typed.
    static func matchExpression(_ query: String) -> String? {
        let words = query
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).replacing("\"", with: "") }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    // MARK: Embeddings

    private func vector(for passage: NoteSnapshot.Passage) -> [Float]? {
        guard let embedding, passage.kind != .title else { return nil }
        let text = passage.heading.isEmpty ? passage.text : "\(passage.heading). \(passage.text)"
        return embedding.vector(for: String(text.prefix(1000))).map { $0.map(Float.init) }
    }

    private func loadVectors(_ db: SQLiteDatabase) -> [Int: [Float]] {
        if let vectors { return vectors }
        var loaded: [Int: [Float]] = [:]
        for (row, data) in (try? db.query("SELECT passage, vector FROM vectors") { ($0.int(0), $0.blob(1)) }) ?? [] {
            loaded[row] = Self.floats(data)
        }
        vectors = loaded
        return loaded
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            na += a[index] * a[index]
            nb += b[index] * b[index]
        }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }

    private static func data(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: Opening

    private func open() -> SQLiteDatabase? {
        if let database { return database }
        do {
            var db = try SQLiteDatabase(url: url)
            let version = try db.query("PRAGMA user_version") { $0.int(0) }.first ?? 0
            if version != Self.version {
                // Built by another version: start again from the notes.
                db = try rebuild()
            }
            database = db
            return db
        } catch {
            return nil
        }
    }

    private func rebuild() throws -> SQLiteDatabase {
        clear()
        let db = try SQLiteDatabase(url: url)
        try db.execute("""
            CREATE VIRTUAL TABLE passages USING fts5(
                note UNINDEXED, kind UNINDEXED, start UNINDEXED, heading, text,
                tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
            )
            """)
        try db.execute("CREATE TABLE vectors (passage INTEGER PRIMARY KEY, note TEXT NOT NULL, vector BLOB NOT NULL)")
        try db.execute("CREATE INDEX vectors_note ON vectors (note)")
        try db.execute("CREATE TABLE notes (id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL)")
        try db.execute("PRAGMA user_version = \(Self.version)")
        return db
    }
}
