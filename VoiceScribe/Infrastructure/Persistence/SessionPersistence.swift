import Foundation
import SQLite3

/// Automatic session persistence using SQLite.
/// Auto-saves every 30s and after each new segment. Crash-resistant.
final class SessionPersistence {

    static let shared = SessionPersistence()

    // Internal for extension access (CoachingPersistence, SQLiteHelper)
    var db: OpaquePointer?
    let dbQueue = DispatchQueue(label: "com.voicescribe.persistence", qos: .utility)
    private var autoSaveTimer: Timer?
    private var pendingSegments: [(sessionId: UUID, segment: TranscriptionSegment)] = []
    let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first.map { $0.appendingPathComponent("VoiceScribe", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoiceScribe", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        } catch {
            Log.persistence.error("Failed to create app support directory: \(error.localizedDescription)")
        }
        dbPath = appSupport.appendingPathComponent("sessions.db").path

        openDatabase()
        createTables()
        createCoachingTables()
        Log.persistence.info("Database: \(self.dbPath)")
    }

    deinit {
        stopAutoSave()
        flushPending()
        if let db = db { sqlite3_close(db) }
    }

    // MARK: - Setup

    private func openDatabase() {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            Log.persistence.error("DB open failed: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
    }

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                start_date REAL NOT NULL,
                end_date REAL
            )
        """)

        exec("""
            CREATE TABLE IF NOT EXISTS segments (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                text TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                speaker TEXT NOT NULL,
                confidence REAL NOT NULL,
                timestamp REAL NOT NULL,
                sentiment_valence REAL,
                sentiment_arousal REAL,
                sentiment_dominance REAL,
                sentiment_confidence REAL,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
        """)

        exec("CREATE INDEX IF NOT EXISTS idx_segments_session ON segments(session_id)")
        exec("CREATE INDEX IF NOT EXISTS idx_segments_time ON segments(start_time)")
        exec("CREATE INDEX IF NOT EXISTS idx_sessions_date ON sessions(start_date DESC)")

        exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS segments_fts USING fts5(
                text, content=segments, content_rowid=rowid
            )
        """)
    }

    // MARK: - Session CRUD

    func saveSession(_ session: TranscriptionSession) {
        dbQueue.async { [weak self] in self?.saveSessionInternal(session) }
    }

    private func saveSessionInternal(_ session: TranscriptionSession) {
        let endDate: SQLValue = session.endDate.map { .double($0.timeIntervalSince1970) } ?? .null
        execute(
            "INSERT OR REPLACE INTO sessions (id, title, start_date, end_date) VALUES (?, ?, ?, ?)",
            [.uuid(session.id), .text(session.title), .double(session.startDate.timeIntervalSince1970), endDate]
        )
    }

    func saveSegment(_ segment: TranscriptionSegment, sessionId: UUID) {
        dbQueue.async { [weak self] in self?.saveSegmentInternal(segment, sessionId: sessionId) }
    }

    private func saveSegmentInternal(_ segment: TranscriptionSegment, sessionId: UUID) {
        let sentimentParams: [SQLValue]
        if let s = segment.sentiment {
            sentimentParams = [.float(s.valence), .float(s.arousal), .float(s.dominance), .float(s.confidence)]
        } else {
            sentimentParams = [.null, .null, .null, .null]
        }

        execute("""
            INSERT OR IGNORE INTO segments
            (id, session_id, text, start_time, end_time, speaker, confidence, timestamp,
             sentiment_valence, sentiment_arousal, sentiment_dominance, sentiment_confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .uuid(segment.id), .uuid(sessionId), .text(segment.text),
            .double(segment.startTime), .double(segment.endTime),
            .text(segment.speaker.rawValue), .float(segment.confidence),
            .double(segment.timestamp.timeIntervalSince1970)
        ] + sentimentParams)

        // FTS index
        execute(
            "INSERT INTO segments_fts(rowid, text) VALUES (last_insert_rowid(), ?)",
            [.text(segment.text)]
        )
    }

    // MARK: - Retrieval

    func loadSessionList() -> [TranscriptionSession] {
        loadSessionList(limit: 50)
    }

    func loadSessionList(limit: Int) -> [TranscriptionSession] {
        query(
            "SELECT id, title, start_date, end_date FROM sessions ORDER BY start_date DESC LIMIT ?",
            [.int(Int32(limit))]
        ) { row in
            TranscriptionSession(
                id: row.uuid(0), title: row.string(1),
                startDate: row.date(2), endDate: row.optionalDate(3),
                segments: []
            )
        }
    }

    func loadSession(id: UUID) -> TranscriptionSession? {
        guard let header: (title: String, start: Date, end: Date?) = queryOne(
            "SELECT title, start_date, end_date FROM sessions WHERE id = ?",
            [.uuid(id)]
        , map: { row in
            (title: row.string(0), start: row.date(1), end: row.optionalDate(2))
        }) else { return nil }

        let segments: [TranscriptionSegment] = query("""
            SELECT id, text, start_time, end_time, speaker, confidence, timestamp,
                   sentiment_valence, sentiment_arousal, sentiment_dominance, sentiment_confidence
            FROM segments WHERE session_id = ? ORDER BY start_time
        """, [.uuid(id)]) { row in
            let sentiment: EmotionalState? = row.isNull(7) ? nil : EmotionalState(
                valence: row.float(7), arousal: row.float(8),
                dominance: row.float(9), confidence: row.float(10)
            )
            return TranscriptionSegment(
                text: row.string(1),
                startTime: row.double(2), endTime: row.double(3),
                speaker: Speaker(rawValue: row.string(4)) ?? .unknown,
                confidence: row.float(5),
                sentiment: sentiment
            )
        }

        return TranscriptionSession(
            id: id, title: header.title,
            startDate: header.start, endDate: header.end,
            segments: segments
        )
    }

    func search(query: String) -> [(session: TranscriptionSession, matchingText: String)] {
        search(query: query, limit: 50)
    }

    func search(query searchQuery: String, limit: Int) -> [(session: TranscriptionSession, matchingText: String)] {
        query("""
            SELECT s.id, s.title, s.start_date, seg.text
            FROM segments seg
            JOIN segments_fts fts ON seg.rowid = fts.rowid
            JOIN sessions s ON seg.session_id = s.id
            WHERE segments_fts MATCH ?
            ORDER BY rank LIMIT ?
        """, [.text(searchQuery), .int(Int32(limit))]) { row in
            let session = TranscriptionSession(
                id: row.uuid(0), title: row.string(1),
                startDate: row.date(2), endDate: nil, segments: []
            )
            return (session, row.string(3))
        }
    }

    func deleteSession(id: UUID) {
        dbQueue.async { [weak self] in
            self?.execute("DELETE FROM segments WHERE session_id = ?", [.uuid(id)])
            self?.execute("DELETE FROM sessions WHERE id = ?", [.uuid(id)])
        }
    }

    // MARK: - Auto-Save

    func startAutoSave(interval: TimeInterval = 30.0) {
        stopAutoSave()
        DispatchQueue.main.async { [weak self] in
            self?.autoSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.flushPending()
            }
        }
    }

    func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        flushPending()
    }

    func queueSegment(_ segment: TranscriptionSegment, sessionId: UUID) {
        dbQueue.async { [weak self] in
            self?.pendingSegments.append((sessionId, segment))
            if (self?.pendingSegments.count ?? 0) >= 20 { self?.flushPendingInternal() }
        }
    }

    private func flushPending() {
        dbQueue.async { [weak self] in self?.flushPendingInternal() }
    }

    private func flushPendingInternal() {
        guard !pendingSegments.isEmpty else { return }
        exec("BEGIN TRANSACTION")
        for item in pendingSegments { saveSegmentInternal(item.segment, sessionId: item.sessionId) }
        exec("COMMIT")
        let count = pendingSegments.count
        pendingSegments.removeAll()
        Log.persistence.debug("Flushed \(count) segments")
    }

    func stats() -> (sessions: Int, segments: Int, dbSizeMB: Double) {
        let sc = scalar("SELECT COUNT(*) FROM sessions")
        let sg = scalar("SELECT COUNT(*) FROM segments")
        let size = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int) ?? 0
        return (sc, sg, Double(size) / 1_048_576.0)
    }

    func exec(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let e = errMsg { Log.persistence.error("SQL: \(String(cString: e))"); sqlite3_free(errMsg) }
        }
    }
}
