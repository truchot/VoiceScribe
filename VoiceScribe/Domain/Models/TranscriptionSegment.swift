import Foundation

struct TranscriptionSegment: Identifiable, Codable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let speaker: Speaker
    let confidence: Float
    let timestamp: Date
    
    /// Sentiment state at the time of this segment (from audio analysis)
    var sentiment: EmotionalState?
    
    init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speaker: Speaker = .unknown,
        confidence: Float = 1.0,
        sentiment: EmotionalState? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.confidence = confidence
        self.timestamp = Date()
        self.sentiment = sentiment
    }
    
    init(
        id: UUID, text: String, startTime: TimeInterval, endTime: TimeInterval,
        speaker: Speaker, confidence: Float, timestamp: Date, sentiment: EmotionalState? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.confidence = confidence
        self.timestamp = timestamp
        self.sentiment = sentiment
    }
    
    var formattedTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Sentiment emoji for compact display
    var sentimentEmoji: String {
        sentiment?.label.emoji ?? ""
    }
}

enum Speaker: String, Codable, CaseIterable {
    case me = "Moi"
    case other = "Participant"
    case unknown = "..."
}

/// Aggregate Root for a transcription session.
///
/// All mutations go through methods that enforce invariants:
/// - Segments are append-only (no external mutation)
/// - Deduplication is enforced at the aggregate boundary
/// - Session lifecycle (finish) is a single atomic operation
/// - Export and analysis operate on guaranteed-consistent state
///
/// External code reads `segments` freely but cannot mutate it.
struct TranscriptionSession: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    private(set) var endDate: Date?
    private(set) var segments: [TranscriptionSegment]
    private(set) var title: String
    
    var isFinished: Bool { endDate != nil }
    
    // MARK: - Creation
    
    init(title: String = "Session") {
        self.id = UUID()
        self.startDate = Date()
        self.segments = []
        self.title = title
    }
    
    /// Reconstitute from persistence (no invariant checks — data is trusted).
    init(id: UUID, title: String, startDate: Date, endDate: Date?, segments: [TranscriptionSegment]) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.segments = segments
    }
    
    // MARK: - Commands (mutations)
    
    /// Add a transcribed segment, enforcing deduplication.
    /// Returns true if the segment was accepted (not a near-duplicate).
    @discardableResult
    mutating func addSegment(_ segment: TranscriptionSegment) -> Bool {
        if let last = segments.last,
           last.speaker == segment.speaker,
           Self.similarity(last.text, segment.text) > CoachingThresholds.dedupSimilarityThreshold {
            return false
        }
        segments.append(segment)
        return true
    }
    
    /// Close the session. Idempotent — calling on a finished session is a no-op.
    mutating func finish() {
        guard endDate == nil else { return }
        endDate = Date()
    }
    
    /// Rename the session.
    mutating func rename(_ newTitle: String) {
        title = newTitle
    }
    
    // MARK: - Queries (read-only)
    
    var segmentCount: Int { segments.count }
    
    var duration: TimeInterval { (endDate ?? Date()).timeIntervalSince(startDate) }
    
    var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%dh%02dm%02ds", h, m, s) : String(format: "%02d:%02d", m, s)
    }
    
    var fullText: String { segments.map(\.text).joined(separator: " ") }
    
    /// Last N segments (for coaching window). Returns a slice (no copy).
    func recentSegments(_ count: Int = 20) -> ArraySlice<TranscriptionSegment> {
        segments.suffix(count)
    }
    
    /// Sentiment summary for the entire session
    func sentimentSummary() -> SentimentSummary {
        let otherSegments = segments.filter { $0.speaker == .other && $0.sentiment != nil }
        guard !otherSegments.isEmpty else { return SentimentSummary() }
        
        let sentiments = otherSegments.compactMap(\.sentiment)
        
        var summary = SentimentSummary()
        summary.averageValence = sentiments.map(\.valence).reduce(0, +) / Float(sentiments.count)
        summary.averageArousal = sentiments.map(\.arousal).reduce(0, +) / Float(sentiments.count)
        summary.averageDominance = sentiments.map(\.dominance).reduce(0, +) / Float(sentiments.count)
        
        // Emotion distribution
        var dist: [EmotionLabel: Int] = [:]
        for s in sentiments { dist[s.label, default: 0] += 1 }
        let total = Float(sentiments.count)
        summary.emotionDistribution = dist.mapValues { Float($0) / total }
        summary.dominantEmotion = dist.max(by: { $0.value < $1.value })?.key ?? .neutral
        
        // Trend: compare first half vs second half
        let half = sentiments.count / 2
        if half > 2 {
            let firstHalf = sentiments.prefix(half).map(\.valence).reduce(0, +) / Float(half)
            let secondHalf = sentiments.suffix(half).map(\.valence).reduce(0, +) / Float(half)
            let delta = secondHalf - firstHalf
            if delta > CoachingThresholds.trendDeltaThreshold { summary.trend = .improving }
            else if delta < -CoachingThresholds.trendDeltaThreshold { summary.trend = .declining }
            else {
                let stdDev = sentiments.map(\.valence).standardDeviation()
                summary.trend = stdDev > CoachingThresholds.trendVolatileStdDev ? .volatile : .stable
            }
        }
        
        return summary
    }
    
    // MARK: - Export
    
    func exportMarkdown() -> String {
        var md = "# \(title)\n"
        md += "**Date:** \(startDate.formatted(date: .long, time: .shortened))\n"
        md += "**Durée:** \(formattedDuration)\n\n"
        
        let summary = sentimentSummary()
        if summary.dominantEmotion != .neutral {
            md += "**Sentiment dominant:** \(summary.dominantEmotion.emoji) \(summary.dominantEmotion.rawValue)\n"
            md += "**Tendance:** \(summary.trend.rawValue)\n\n"
        }
        
        md += "---\n\n"
        for segment in segments {
            let emoji = segment.sentimentEmoji
            md += "**[\(segment.formattedTime)]** \(emoji) _\(segment.speaker.rawValue)_: \(segment.text)\n\n"
        }
        return md
    }
    
    func exportSRT() -> String {
        var srt = ""
        for (i, seg) in segments.enumerated() {
            srt += "\(i + 1)\n\(formatSRT(seg.startTime)) --> \(formatSRT(seg.endTime))\n\(seg.text)\n\n"
        }
        return srt
    }
    
    private func formatSRT(_ s: TimeInterval) -> String {
        String(format: "%02d:%02d:%02d,%03d", Int(s)/3600, (Int(s)%3600)/60, Int(s)%60,
               Int((s.truncatingRemainder(dividingBy: 1)) * 1000))
    }
    
    // MARK: - Private: Deduplication
    
    /// Text similarity score (0-1) using prefix match and Jaccard overlap.
    private static func similarity(_ a: String, _ b: String) -> Double {
        let aL = a.lowercased(), bL = b.lowercased()
        if aL == bL { return 1.0 }
        let m = max(a.count, b.count)
        guard m > 0 else { return 1.0 }
        let prefixMatch = Double(zip(aL, bL).prefix(while: { $0 == $1 }).count) / Double(m)
        let aWords = Set(aL.split(separator: " "))
        let bWords = Set(bL.split(separator: " "))
        let union = aWords.union(bWords)
        let intersection = aWords.intersection(bWords)
        let jaccardSim = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
        return max(prefixMatch, jaccardSim)
    }
}

// MARK: - Array Extension

extension Array where Element == Float {
    func standardDeviation() -> Float {
        guard count > 1 else { return 0 }
        let mean = reduce(0, +) / Float(count)
        let sumSq = reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
        return sqrt(sumSq / Float(count - 1))
    }
}
