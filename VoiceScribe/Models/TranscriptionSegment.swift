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

struct TranscriptionSession: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var segments: [TranscriptionSegment]
    var title: String
    
    init(title: String = "Session") {
        self.id = UUID()
        self.startDate = Date()
        self.segments = []
        self.title = title
    }
    
    init(id: UUID, title: String, startDate: Date, endDate: Date?, segments: [TranscriptionSegment]) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.segments = segments
    }
    
    var duration: TimeInterval { (endDate ?? Date()).timeIntervalSince(startDate) }
    
    var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%dh%02dm%02ds", h, m, s) : String(format: "%02d:%02d", m, s)
    }
    
    var fullText: String { segments.map(\.text).joined(separator: " ") }
    
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
            if delta > 0.15 { summary.trend = .improving }
            else if delta < -0.15 { summary.trend = .declining }
            else {
                let stdDev = sentiments.map(\.valence).standardDeviation()
                summary.trend = stdDev > 0.3 ? .volatile : .stable
            }
        }
        
        return summary
    }
    
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
