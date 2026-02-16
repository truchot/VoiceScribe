import Foundation

// MARK: - Emotional Dimensions (Russell's Circumplex)

/// Core emotional state derived from audio prosody.
/// Uses the dimensional model (valence × arousal) rather than discrete emotions
/// because it's more reliable from audio-only analysis and maps better to
/// commercial contexts.
struct EmotionalState: Codable {
    /// Positive ↔ Negative (-1.0 to 1.0)
    /// High: enthusiastic, agreeing, satisfied
    /// Low: frustrated, objecting, dissatisfied
    var valence: Float = 0.0
    
    /// Excited ↔ Calm (-1.0 to 1.0)
    /// High: animated, engaged, nervous
    /// Low: bored, disengaged, reflective
    var arousal: Float = 0.0
    
    /// Dominant ↔ Submissive (-1.0 to 1.0)
    /// High: confident, assertive, decided
    /// Low: hesitant, unsure, yielding
    var dominance: Float = 0.0
    
    /// Confidence in the analysis (0.0 to 1.0)
    var confidence: Float = 0.0
    
    /// Derived discrete label (for UI display)
    var label: EmotionLabel {
        if confidence < CoachingThresholds.emotionMinConfidence { return .neutral }
        
        let vt = CoachingThresholds.emotionValenceThreshold
        let at = CoachingThresholds.emotionArousalThreshold
        let dt = CoachingThresholds.emotionDominanceThreshold
        
        // Map circumplex to labels relevant for sales
        if valence > vt && arousal > at { return .enthusiastic }
        if valence > vt && arousal < -at { return .satisfied }
        if valence < -vt && arousal > at { return .frustrated }
        if valence < -vt && arousal < -at { return .disengaged }
        if dominance < -dt { return .hesitant }
        if dominance > dt && valence > 0 { return .confident }
        if arousal > CoachingThresholds.emotionAnimatedArousal { return .animated }
        return .neutral
    }
}

enum EmotionLabel: String, Codable, CaseIterable {
    case enthusiastic = "Enthousiaste"
    case satisfied = "Satisfait"
    case confident = "Confiant"
    case animated = "Animé"
    case neutral = "Neutre"
    case hesitant = "Hésitant"
    case frustrated = "Frustré"
    case disengaged = "Désengagé"
    
    var emoji: String {
        switch self {
        case .enthusiastic: return "🤩"
        case .satisfied: return "😊"
        case .confident: return "😎"
        case .animated: return "😃"
        case .neutral: return "😐"
        case .hesitant: return "🤔"
        case .frustrated: return "😤"
        case .disengaged: return "😶"
        }
    }
    
    /// Commercial signal: positive (buying), negative (risk), or neutral
    var commercialSignal: CommercialSignal {
        switch self {
        case .enthusiastic, .satisfied, .confident: return .positive
        case .animated, .neutral: return .neutral
        case .hesitant, .frustrated, .disengaged: return .negative
        }
    }
}

enum CommercialSignal: String, Codable {
    case positive = "✅"
    case neutral = "➖"
    case negative = "⚠️"
}

// MARK: - Prosodic Features (raw audio measurements)

/// Low-level audio features extracted in real-time (~50ms per frame).
/// These are the raw measurements before interpretation.
struct ProsodicFeatures {
    // Energy
    var rmsEnergy: Float = 0          // Overall loudness
    var energyDelta: Float = 0        // Change in energy (sudden = emphasis)
    
    // Pitch (F0)
    var pitchHz: Float = 0            // Fundamental frequency
    var pitchDelta: Float = 0         // Pitch movement (rising = question)
    var pitchVariability: Float = 0   // Pitch range (monotone vs expressive)
    var pitchContour: PitchContour = .flat
    
    // Rhythm
    var speechRate: Float = 0         // Estimated syllables per second
    var pauseDuration: Float = 0      // Current pause length in seconds
    var pauseFrequency: Float = 0     // Pauses per minute
    
    // Spectral
    var spectralTilt: Float = 0       // High-freq energy ratio (effort/stress)
    var spectralCentroid: Float = 0   // Brightness of voice
    
    // Voice quality
    var harmonicToNoise: Float = 0    // Clean voice vs breathy/tense
    var jitter: Float = 0             // Pitch perturbation (stress indicator)
    
    var isSpeech: Bool = false
    var timestamp: TimeInterval = 0
}

enum PitchContour: String, Codable {
    case rising = "↗"      // Question, uncertainty
    case falling = "↘"     // Statement, certainty
    case flat = "→"        // Neutral
    case peaked = "⌃"      // Emphasis, surprise
    case dipped = "⌄"      // Hesitation mid-sentence
}

// MARK: - Sentiment Timeline

/// A point in the sentiment timeline, recorded every ~500ms
struct SentimentPoint: Identifiable, Codable {
    let id: Int
    let timestamp: TimeInterval
    let emotion: EmotionalState
    let features: SentimentPointFeatures
    
    private static var nextId = 0
    
    init(timestamp: TimeInterval, emotion: EmotionalState, features: SentimentPointFeatures) {
        self.id = SentimentPoint.nextId
        SentimentPoint.nextId += 1
        self.timestamp = timestamp
        self.emotion = emotion
        self.features = features
    }
}

/// Codable subset of ProsodicFeatures for storage
struct SentimentPointFeatures: Codable {
    var energy: Float
    var pitchHz: Float
    var pitchContour: PitchContour
    var speechRate: Float
    var pauseDuration: Float
}

// MARK: - Sentiment Summary (for a segment or session)

struct SentimentSummary: Codable {
    var averageValence: Float = 0
    var averageArousal: Float = 0
    var averageDominance: Float = 0
    var dominantEmotion: EmotionLabel = .neutral
    var emotionDistribution: [EmotionLabel: Float] = [:]
    var hesitationCount: Int = 0
    var questionCount: Int = 0        // Rising pitch contours
    var emphasisCount: Int = 0        // Energy spikes
    var trend: SentimentTrend = .stable
    
    enum SentimentTrend: String, Codable {
        case improving = "↗ Amélioration"
        case declining = "↘ Dégradation"
        case stable = "→ Stable"
        case volatile = "↕ Volatile"
    }
}
