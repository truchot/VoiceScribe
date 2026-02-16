import SwiftUI

/// Focused observable for sentiment analysis state.
///
/// This store updates frequently (~500ms) with emotion data.
/// By isolating it, only views that display sentiment (overlay, coaching)
/// re-render on updates. The transcription list, session history,
/// and control bar are unaffected.
@MainActor
final class SentimentStore: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var currentEmotion = EmotionalState()
    @Published private(set) var currentFeatures = ProsodicFeatures()
    @Published var lastSentimentShift: (from: EmotionLabel, to: EmotionLabel)?
    @Published var sentimentEnabled = true
    
    /// Commercial alert from text analysis (objection, buying signal, etc.)
    @Published private(set) var commercialAlert: CommercialAlert?
    
    /// Recent text signals for coaching context
    @Published private(set) var recentTextSignals: [TextSignalAnalyzer.DetectedSignal] = []
    
    /// Source of the last emotion update (prosody, text override, blended)
    @Published private(set) var dominantSource: HybridSentiment.HybridResult.Source = .prosody
    
    // MARK: - Non-Published Timeline (no view observes this directly)
    
    /// Circular buffer for sentiment history. NOT @Published to avoid
    /// O(n) CoW + SwiftUI diff every 500ms. Views read on-demand via snapshot().
    private var timelineBuffer: [SentimentPoint?]
    private var timelineWriteIndex: Int = 0
    private var timelineCount: Int = 0
    
    // MARK: - Settings
    
    @AppStorage("sentimentSmoothingFactor") var sentimentSmoothing: Double = 0.7
    
    // MARK: - Internal
    
    /// Latest emotion from system audio (used to tag segments)
    private(set) var latestSystemEmotion = EmotionalState()
    
    /// Max timeline points (600 = ~5 min at 500ms intervals)
    private let maxTimelinePoints = 600
    
    init() {
        self.timelineBuffer = [SentimentPoint?](repeating: nil, count: 600)
    }
    
    // MARK: - Updates (called from coordinator)
    
    func updateSentiment(emotion: EmotionalState, features: ProsodicFeatures) {
        currentEmotion = emotion
        currentFeatures = features
        latestSystemEmotion = emotion
        
        let point = SentimentPoint(
            timestamp: features.timestamp,
            emotion: emotion,
            features: SentimentPointFeatures(
                energy: features.rmsEnergy,
                pitchHz: features.pitchHz,
                pitchContour: features.pitchContour,
                speechRate: features.speechRate,
                pauseDuration: features.pauseDuration
            )
        )
        // Circular write — no CoW, no removeFirst shift
        timelineBuffer[timelineWriteIndex % maxTimelinePoints] = point
        timelineWriteIndex += 1
        timelineCount = min(timelineCount + 1, maxTimelinePoints)
    }
    
    /// Read-only snapshot of timeline for analytics/export.
    /// Only called on-demand, not on every update.
    func timelineSnapshot() -> [SentimentPoint] {
        guard timelineCount > 0 else { return [] }
        var result: [SentimentPoint] = []
        result.reserveCapacity(timelineCount)
        let start = timelineWriteIndex >= maxTimelinePoints
            ? timelineWriteIndex % maxTimelinePoints : 0
        for i in 0..<timelineCount {
            if let pt = timelineBuffer[(start + i) % maxTimelinePoints] {
                result.append(pt)
            }
        }
        return result
    }
    
    /// Update with hybrid (prosody + text) result.
    func updateHybrid(_ result: HybridSentiment.HybridResult) {
        currentEmotion = result.emotion
        latestSystemEmotion = result.emotion
        dominantSource = result.dominantSource
        recentTextSignals = result.textSignals
        
        if let alert = result.commercialAlert {
            commercialAlert = alert
        }
    }
    
    func dismissAlert() {
        commercialAlert = nil
    }
    
    func reportShift(from: EmotionLabel, to: EmotionLabel) {
        lastSentimentShift = (from: from, to: to)
    }
    
    func dismissShift() {
        lastSentimentShift = nil
    }
    
    func reset() {
        currentEmotion = EmotionalState()
        currentFeatures = ProsodicFeatures()
        timelineWriteIndex = 0
        timelineCount = 0
        lastSentimentShift = nil
        latestSystemEmotion = EmotionalState()
        commercialAlert = nil
        recentTextSignals.removeAll()
        dominantSource = .prosody
    }
}
