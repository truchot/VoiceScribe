import Foundation
import SQLite3

/// Extends SessionPersistence with coaching-specific persistence.
///
/// Tables:
/// - coaching_snapshots: periodic state captures (~every coaching update)
/// - coaching_memory: captured memory slots (prospect name, budget, pain...)
/// - coaching_tips: triggered tips and their urgency
/// - coaching_alerts: commercial text-based alerts (objections, buying signals)
/// - coaching_reports: finalized post-call report markdown
extension SessionPersistence {

    // MARK: - Schema

    func createCoachingTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS coaching_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                movement TEXT NOT NULL,
                act TEXT NOT NULL,
                is_manual_override INTEGER NOT NULL DEFAULT 0,
                fluidity_score REAL NOT NULL,
                readiness_score REAL NOT NULL,
                speaker_balance_my_ratio REAL NOT NULL,
                speaker_balance_healthy INTEGER NOT NULL,
                focus_text TEXT,
                action_phrase TEXT,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_snapshots_session ON coaching_snapshots(session_id)")
        exec("CREATE INDEX IF NOT EXISTS idx_snapshots_time ON coaching_snapshots(session_id, timestamp)")

        exec("""
            CREATE TABLE IF NOT EXISTS coaching_memory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                slot_key TEXT NOT NULL,
                slot_value TEXT NOT NULL,
                movement TEXT NOT NULL,
                source TEXT NOT NULL,
                confidence REAL NOT NULL,
                timestamp REAL NOT NULL,
                previous_value TEXT,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_memory_session ON coaching_memory(session_id)")
        exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_session_key ON coaching_memory(session_id, slot_key)")

        exec("""
            CREATE TABLE IF NOT EXISTS coaching_tips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                advice TEXT NOT NULL,
                trigger_desc TEXT NOT NULL,
                urgency TEXT NOT NULL,
                movement TEXT NOT NULL,
                alternatives TEXT,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_tips_session ON coaching_tips(session_id)")

        exec("""
            CREATE TABLE IF NOT EXISTS coaching_alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                alert_type TEXT NOT NULL,
                category TEXT NOT NULL,
                message TEXT NOT NULL,
                strength REAL NOT NULL,
                matched_text TEXT,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_alerts_session ON coaching_alerts(session_id)")

        exec("""
            CREATE TABLE IF NOT EXISTS coaching_reports (
                session_id TEXT PRIMARY KEY,
                report_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                total_duration REAL NOT NULL,
                movement_count INTEGER NOT NULL,
                avg_fluidity REAL NOT NULL,
                qualification_score REAL NOT NULL,
                discovery_score REAL NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
        """)

        Log.persistence.info("Coaching tables ready")
    }

    // MARK: - DTOs

    struct CoachingSnapshot {
        let sessionId: UUID
        let timestamp: TimeInterval
        let movement: ConversationMovement
        let act: ConversationAct
        let isManualOverride: Bool
        let fluidityScore: Float
        let readinessScore: Float
        let speakerBalanceMyRatio: Float
        let speakerBalanceHealthy: Bool
        let focusText: String?
        let actionPhrase: String?
    }

    struct PersistedMemorySlot {
        let sessionId: UUID
        let key: String
        let value: String
        let movement: ConversationMovement
        let source: ConversationMemory.CaptureSource
        let confidence: Float
        let timestamp: TimeInterval
        let previousValue: String?
    }

    struct PersistedTip {
        let sessionId: UUID
        let timestamp: TimeInterval
        let advice: String
        let trigger: String
        let urgency: String
        let movement: ConversationMovement
        let alternatives: [String]
    }

    struct PersistedAlert {
        let sessionId: UUID
        let timestamp: TimeInterval
        let alertType: String
        let category: String
        let message: String
        let strength: Float
        let matchedText: String?
    }

    struct MovementStat {
        let movement: ConversationMovement
        let snapshotCount: Int
        let avgFluidity: Float
        let manualOverrideCount: Int
    }

    struct ObjectionStat {
        let category: String
        let count: Int
        let avgStrength: Float
    }

    struct CoachingStatsSummary {
        let snapshots: Int
        let memorySlots: Int
        let tips: Int
        let alerts: Int
        let reports: Int
        var totalRows: Int { snapshots + memorySlots + tips + alerts + reports }
    }

    // MARK: - Write (all async on dbQueue)

    func saveCoachingSnapshot(_ s: CoachingSnapshot) {
        dbQueue.async { [weak self] in
            self?.execute("""
                INSERT INTO coaching_snapshots
                (session_id, timestamp, movement, act, is_manual_override,
                 fluidity_score, readiness_score, speaker_balance_my_ratio,
                 speaker_balance_healthy, focus_text, action_phrase)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .uuid(s.sessionId), .double(s.timestamp),
                .int(Int32(s.movement.rawValue)), .text(s.act.rawValue),
                .bool(s.isManualOverride),
                .float(s.fluidityScore), .float(s.readinessScore),
                .float(s.speakerBalanceMyRatio), .bool(s.speakerBalanceHealthy),
                .optionalText(s.focusText), .optionalText(s.actionPhrase)
            ])
        }
    }

    func saveMemorySlot(_ s: PersistedMemorySlot) {
        dbQueue.async { [weak self] in
            self?.execute("""
                INSERT INTO coaching_memory
                (session_id, slot_key, slot_value, movement, source, confidence, timestamp, previous_value)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id, slot_key) DO UPDATE SET
                    slot_value = excluded.slot_value,
                    confidence = excluded.confidence,
                    timestamp = excluded.timestamp,
                    previous_value = coaching_memory.slot_value
            """, [
                .uuid(s.sessionId), .text(s.key), .text(s.value),
                .int(Int32(s.movement.rawValue)), .text(s.source.rawValue),
                .float(s.confidence), .double(s.timestamp),
                .optionalText(s.previousValue)
            ])
        }
    }

    func saveTip(_ t: PersistedTip) {
        dbQueue.async { [weak self] in
            let altJson = (try? JSONEncoder().encode(t.alternatives))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            self?.execute("""
                INSERT INTO coaching_tips
                (session_id, timestamp, advice, trigger_desc, urgency, movement, alternatives)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [
                .uuid(t.sessionId), .double(t.timestamp),
                .text(t.advice), .text(t.trigger), .text(t.urgency),
                .int(Int32(t.movement.rawValue)), .text(altJson)
            ])
        }
    }

    func saveCommercialAlert(_ a: PersistedAlert) {
        dbQueue.async { [weak self] in
            self?.execute("""
                INSERT INTO coaching_alerts
                (session_id, timestamp, alert_type, category, message, strength, matched_text)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [
                .uuid(a.sessionId), .double(a.timestamp),
                .text(a.alertType), .text(a.category), .text(a.message),
                .float(a.strength), .optionalText(a.matchedText)
            ])
        }
    }

    func saveReport(sessionId: UUID, report: PostCallReport) {
        dbQueue.async { [weak self] in
            self?.execute("""
                INSERT OR REPLACE INTO coaching_reports
                (session_id, report_json, created_at, total_duration, movement_count,
                 avg_fluidity, qualification_score, discovery_score)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .uuid(sessionId), .text(report.toMarkdown()),
                .double(Date().timeIntervalSince1970), .double(report.totalDuration),
                .int(Int32(report.movementCount)), .float(report.averageFluidityScore),
                .float(report.memoryReport.qualificationScore),
                .float(report.memoryReport.discoveryScore)
            ])
        }
    }

    // MARK: - Read

    func loadSnapshots(sessionId: UUID) -> [CoachingSnapshot] {
        query("""
            SELECT timestamp, movement, act, is_manual_override,
                   fluidity_score, readiness_score, speaker_balance_my_ratio,
                   speaker_balance_healthy, focus_text, action_phrase
            FROM coaching_snapshots WHERE session_id = ? ORDER BY timestamp
        """, [.uuid(sessionId)]) { row in
            CoachingSnapshot(
                sessionId: sessionId,
                timestamp: row.double(0),
                movement: ConversationMovement(rawValue: row.int(1)) ?? .accueil,
                act: ConversationAct(rawValue: row.string(2)) ?? .connexion,
                isManualOverride: row.bool(3),
                fluidityScore: row.float(4), readinessScore: row.float(5),
                speakerBalanceMyRatio: row.float(6), speakerBalanceHealthy: row.bool(7),
                focusText: row.optionalText(8), actionPhrase: row.optionalText(9)
            )
        }
    }

    func loadMemorySlots(sessionId: UUID) -> [PersistedMemorySlot] {
        query("""
            SELECT slot_key, slot_value, movement, source, confidence, timestamp, previous_value
            FROM coaching_memory WHERE session_id = ? ORDER BY timestamp
        """, [.uuid(sessionId)]) { row in
            PersistedMemorySlot(
                sessionId: sessionId,
                key: row.string(0), value: row.string(1),
                movement: ConversationMovement(rawValue: row.int(2)) ?? .accueil,
                source: ConversationMemory.CaptureSource(rawValue: row.string(3)) ?? .autoDetected,
                confidence: row.float(4), timestamp: row.double(5),
                previousValue: row.optionalText(6)
            )
        }
    }

    func loadTips(sessionId: UUID) -> [PersistedTip] {
        query("""
            SELECT timestamp, advice, trigger_desc, urgency, movement, alternatives
            FROM coaching_tips WHERE session_id = ? ORDER BY timestamp
        """, [.uuid(sessionId)]) { row in
            var alts: [String] = []
            if let altStr = row.text(5), let data = altStr.data(using: .utf8) {
                alts = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            return PersistedTip(
                sessionId: sessionId,
                timestamp: row.double(0), advice: row.string(1),
                trigger: row.string(2), urgency: row.string(3),
                movement: ConversationMovement(rawValue: row.int(4)) ?? .accueil,
                alternatives: alts
            )
        }
    }

    func loadAlerts(sessionId: UUID) -> [PersistedAlert] {
        query("""
            SELECT timestamp, alert_type, category, message, strength, matched_text
            FROM coaching_alerts WHERE session_id = ? ORDER BY timestamp
        """, [.uuid(sessionId)]) { row in
            PersistedAlert(
                sessionId: sessionId,
                timestamp: row.double(0),
                alertType: row.string(1), category: row.string(2),
                message: row.string(3), strength: row.float(4),
                matchedText: row.optionalText(5)
            )
        }
    }

    func loadReport(sessionId: UUID) -> String? {
        queryOne(
            "SELECT report_json FROM coaching_reports WHERE session_id = ?",
            [.uuid(sessionId)]
        ) { $0.text(0) }
    }

    // MARK: - Cross-Session Analytics

    func movementStats(limit: Int = 20) -> [MovementStat] {
        query("""
            SELECT s.movement, COUNT(*) as cnt,
                   AVG(s.fluidity_score) as avg_flu,
                   SUM(CASE WHEN s.is_manual_override THEN 1 ELSE 0 END) as manual_cnt
            FROM coaching_snapshots s
            GROUP BY s.movement ORDER BY cnt DESC
        """) { row in
            MovementStat(
                movement: ConversationMovement(rawValue: row.int(0)) ?? .accueil,
                snapshotCount: row.int(1),
                avgFluidity: row.float(2),
                manualOverrideCount: row.int(3)
            )
        }
    }

    func objectionStats(limit: Int = 20) -> [ObjectionStat] {
        query("""
            SELECT category, COUNT(*) as cnt, AVG(strength) as avg_str
            FROM coaching_alerts WHERE alert_type = 'objection'
            GROUP BY category ORDER BY cnt DESC
        """) { row in
            ObjectionStat(
                category: row.string(0),
                count: row.int(1),
                avgStrength: row.float(2)
            )
        }
    }

    func qualificationTrend(limit: Int = 20) -> [(sessionId: UUID, date: Date, score: Float)] {
        query("""
            SELECT r.session_id, s.start_date, r.qualification_score
            FROM coaching_reports r
            JOIN sessions s ON r.session_id = s.id
            ORDER BY s.start_date DESC LIMIT ?
        """, [.int(Int32(limit))]) { row in
            (sessionId: row.uuid(0), date: row.date(1), score: row.float(2))
        }
    }

    func reconstructTimeline(sessionId: UUID) -> [(movement: ConversationMovement, start: TimeInterval, end: TimeInterval)] {
        let snapshots = loadSnapshots(sessionId: sessionId)
        guard !snapshots.isEmpty else { return [] }

        var timeline: [(movement: ConversationMovement, start: TimeInterval, end: TimeInterval)] = []
        var current = snapshots[0].movement
        var start = snapshots[0].timestamp

        for s in snapshots.dropFirst() {
            if s.movement != current {
                timeline.append((current, start, s.timestamp))
                current = s.movement
                start = s.timestamp
            }
        }
        timeline.append((current, start, snapshots.last?.timestamp ?? start))
        return timeline
    }

    func coachingStats() -> CoachingStatsSummary {
        CoachingStatsSummary(
            snapshots: scalar("SELECT COUNT(*) FROM coaching_snapshots"),
            memorySlots: scalar("SELECT COUNT(*) FROM coaching_memory"),
            tips: scalar("SELECT COUNT(*) FROM coaching_tips"),
            alerts: scalar("SELECT COUNT(*) FROM coaching_alerts"),
            reports: scalar("SELECT COUNT(*) FROM coaching_reports")
        )
    }
}
