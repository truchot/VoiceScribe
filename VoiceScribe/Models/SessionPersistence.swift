import Foundation
import SQLite3

/// Automatic session persistence using SQLite.
/// Auto-saves every 30s and after each new segment. Crash-resistant.
final class SessionPersistence {
    
    static let shared = SessionPersistence()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.voicescribe.persistence", qos: .utility)
    private var autoSaveTimer: Timer?
    private var pendingSegments: [(sessionId: UUID, segment: TranscriptionSegment)] = []
    private let dbPath: String
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("VoiceScribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        dbPath = appSupport.appendingPathComponent("sessions.db").path
        
        openDatabase()
        createTables()
        print("💾 Database: \(dbPath)")
    }
    
    deinit {
        stopAutoSave()
        flushPending()
        if let db = db { sqlite3_close(db) }
    }
    
    // MARK: - Setup
    
    private func openDatabase() {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            print("❌ DB open failed: \(String(cString: sqlite3_errmsg(db)))")
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
        let sql = "INSERT OR REPLACE INTO sessions (id, title, start_date, end_date) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, session.id.uuidString, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_text(stmt, 2, session.title, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_double(stmt, 3, session.startDate.timeIntervalSince1970)
        if let end = session.endDate { sqlite3_bind_double(stmt, 4, end.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, 4) }
        sqlite3_step(stmt)
    }
    
    func saveSegment(_ segment: TranscriptionSegment, sessionId: UUID) {
        dbQueue.async { [weak self] in self?.saveSegmentInternal(segment, sessionId: sessionId) }
    }
    
    private func saveSegmentInternal(_ segment: TranscriptionSegment, sessionId: UUID) {
        let sql = """
            INSERT OR IGNORE INTO segments
            (id, session_id, text, start_time, end_time, speaker, confidence, timestamp,
             sentiment_valence, sentiment_arousal, sentiment_dominance, sentiment_confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, segment.id.uuidString, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_text(stmt, 2, sessionId.uuidString, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_text(stmt, 3, segment.text, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_double(stmt, 4, segment.startTime)
        sqlite3_bind_double(stmt, 5, segment.endTime)
        sqlite3_bind_text(stmt, 6, segment.speaker.rawValue, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_double(stmt, 7, Double(segment.confidence))
        sqlite3_bind_double(stmt, 8, segment.timestamp.timeIntervalSince1970)
        
        if let s = segment.sentiment {
            sqlite3_bind_double(stmt, 9, Double(s.valence))
            sqlite3_bind_double(stmt, 10, Double(s.arousal))
            sqlite3_bind_double(stmt, 11, Double(s.dominance))
            sqlite3_bind_double(stmt, 12, Double(s.confidence))
        } else {
            sqlite3_bind_null(stmt, 9)
            sqlite3_bind_null(stmt, 10)
            sqlite3_bind_null(stmt, 11)
            sqlite3_bind_null(stmt, 12)
        }
        
        sqlite3_step(stmt)
        
        // FTS
        let ftsSql = "INSERT INTO segments_fts(rowid, text) VALUES (last_insert_rowid(), ?)"
        var ftsStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, ftsSql, -1, &ftsStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(ftsStmt, 1, segment.text, -1, SQLITE_TRANSIENT_PTR)
            sqlite3_step(ftsStmt)
            sqlite3_finalize(ftsStmt)
        }
    }
    
    // MARK: - Retrieval
    
    func loadSessionList(limit: Int = 50) -> [TranscriptionSession] {
        var sessions: [TranscriptionSession] = []
        let sql = "SELECT id, title, start_date, end_date FROM sessions ORDER BY start_date DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0),
                  let titleStr = sqlite3_column_text(stmt, 1) else { continue }
            let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
            let title = String(cString: titleStr)
            let startDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            let endDate: Date? = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)) : nil
            sessions.append(TranscriptionSession(id: id, title: title, startDate: startDate, endDate: endDate, segments: []))
        }
        return sessions
    }
    
    func loadSession(id: UUID) -> TranscriptionSession? {
        let sql = "SELECT title, start_date, end_date FROM sessions WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT_PTR)
        
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let titleStr = sqlite3_column_text(stmt, 0) else { return nil }
        let title = String(cString: titleStr)
        let startDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let endDate: Date? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)) : nil
        
        // Load segments with sentiment
        let segSql = """
            SELECT id, text, start_time, end_time, speaker, confidence, timestamp,
                   sentiment_valence, sentiment_arousal, sentiment_dominance, sentiment_confidence
            FROM segments WHERE session_id = ? ORDER BY start_time
        """
        var segStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, segSql, -1, &segStmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(segStmt) }
        sqlite3_bind_text(segStmt, 1, id.uuidString, -1, SQLITE_TRANSIENT_PTR)
        
        var segments: [TranscriptionSegment] = []
        while sqlite3_step(segStmt) == SQLITE_ROW {
            guard let textStr = sqlite3_column_text(segStmt, 1),
                  let speakerStr = sqlite3_column_text(segStmt, 4) else { continue }
            
            var sentiment: EmotionalState? = nil
            if sqlite3_column_type(segStmt, 7) != SQLITE_NULL {
                sentiment = EmotionalState(
                    valence: Float(sqlite3_column_double(segStmt, 7)),
                    arousal: Float(sqlite3_column_double(segStmt, 8)),
                    dominance: Float(sqlite3_column_double(segStmt, 9)),
                    confidence: Float(sqlite3_column_double(segStmt, 10))
                )
            }
            
            segments.append(TranscriptionSegment(
                text: String(cString: textStr),
                startTime: sqlite3_column_double(segStmt, 2),
                endTime: sqlite3_column_double(segStmt, 3),
                speaker: Speaker(rawValue: String(cString: speakerStr)) ?? .unknown,
                confidence: Float(sqlite3_column_double(segStmt, 5)),
                sentiment: sentiment
            ))
        }
        
        return TranscriptionSession(id: id, title: title, startDate: startDate, endDate: endDate, segments: segments)
    }
    
    func search(query: String, limit: Int = 50) -> [(session: TranscriptionSession, matchingText: String)] {
        let sql = """
            SELECT s.id, s.title, s.start_date, seg.text
            FROM segments seg
            JOIN segments_fts fts ON seg.rowid = fts.rowid
            JOIN sessions s ON seg.session_id = s.id
            WHERE segments_fts MATCH ?
            ORDER BY rank LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, query, -1, SQLITE_TRANSIENT_PTR)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        
        var results: [(session: TranscriptionSession, matchingText: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0),
                  let titleStr = sqlite3_column_text(stmt, 1),
                  let textStr = sqlite3_column_text(stmt, 3) else { continue }
            let session = TranscriptionSession(
                id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
                title: String(cString: titleStr),
                startDate: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                endDate: nil, segments: []
            )
            results.append((session, String(cString: textStr)))
        }
        return results
    }
    
    func deleteSession(id: UUID) {
        dbQueue.async { [weak self] in
            self?.exec("DELETE FROM segments WHERE session_id = '\(id.uuidString)'")
            self?.exec("DELETE FROM sessions WHERE id = '\(id.uuidString)'")
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
        print("💾 Flushed \(count) segments")
    }
    
    func stats() -> (sessions: Int, segments: Int, dbSizeMB: Double) {
        var sc = 0, sg = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sessions", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { sc = Int(sqlite3_column_int(stmt, 0)) }
            sqlite3_finalize(stmt)
        }
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM segments", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { sg = Int(sqlite3_column_int(stmt, 0)) }
            sqlite3_finalize(stmt)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int) ?? 0
        return (sc, sg, Double(size) / 1_048_576.0)
    }
    
    private func exec(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let e = errMsg { print("❌ SQL: \(String(cString: e))"); sqlite3_free(errMsg) }
        }
    }
}

private let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
