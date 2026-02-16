import Foundation

// MARK: - Coaching Configuration
//
// All tunable thresholds and timing constants for the coaching engine.
// Centralizes magic numbers from MovementDetector, ConversationCoach,
// and RecordingCoordinator into one testable, documentable place.

struct CoachingThresholds {

    // MARK: - Movement Detection

    /// Minimum confidence to switch movement (0-1). Lower = more sensitive.
    static let movementSwitchConfidence: Float = 0.30

    /// Minimum absolute score to switch movement. Prevents noise-triggered switches.
    static let movementSwitchMinScore: Float = 2.5

    /// Bonus score for staying in current movement (continuity bias).
    static let continuityBonus: Float = 2.0

    /// Multiplier for backward movement scores (penalize going back).
    static let backwardPenalty: Float = 0.4

    /// Score bonus for temporal alignment with expected schedule.
    static let temporalBiasBonus: Float = 0.3

    /// Score weight per recently-filled memory slot.
    static let memorySlotWeight: Float = 0.8

    /// Max age (seconds) for a memory slot to be considered "recently filled".
    static let recentSlotWindow: TimeInterval = 120

    // MARK: - Speaker Balance

    /// Tolerance band around ideal ratio before flagging imbalance.
    static let balanceTolerance: Float = 0.15

    // MARK: - Emotion Scoring

    /// Emotion bonus for dialogue-suggesting emotions (frustrated/hesitant).
    static let emotionDialogueBonus: Float = 0.6

    /// Emotion bonus for engagement-suggesting emotions (enthusiastic/confident).
    static let emotionEngagementBonus: Float = 0.4

    /// Minimum emotion confidence to generate emotion coaching.
    static let emotionCoachingMinConfidence: Float = 0.4

    /// Movement progress threshold below which we show "early" suggestions.
    static let earlyProgressThreshold: Float = 0.3

    // MARK: - Transition Timing

    /// Overtime ratio to start suggesting transitions (0.6 = 60% of max duration).
    static let transitionSuggestRatio: Double = 0.6

    /// Overtime ratio to force-suggest moving to next movement.
    static let overtimeForceRatio: Double = 1.5

    // MARK: - Fluidity Scoring

    /// Base fluidity score (starts "good", penalties bring it down).
    static let fluidityBase: Float = 0.7

    /// Penalty for unhealthy speaker balance.
    static let fluidityBalancePenalty: Float = 0.15

    /// Penalty for exceeding movement max duration × overtimeForceRatio.
    static let fluidityOvertimePenalty: Float = 0.2

    /// Bonus multiplier for memory readiness (readiness × this value).
    static let fluidityMemoryBonus: Float = 0.2

    /// Movement history count above which we penalize (chaotic conversation).
    static let fluidityMaxMovements: Int = 15

    /// Penalty for exceeding fluidityMaxMovements.
    static let fluidityChaotisPenalty: Float = 0.15

    // MARK: - Persistence

    /// Interval between coaching snapshot saves (seconds).
    static let snapshotInterval: TimeInterval = 3.0

    // MARK: - Emotion Classification (EmotionalState.label)

    /// Minimum confidence to derive any emotion label (below → .neutral).
    static let emotionMinConfidence: Float = 0.3

    /// Valence threshold for positive/negative classification.
    static let emotionValenceThreshold: Float = 0.3

    /// Arousal threshold for high/low energy classification.
    static let emotionArousalThreshold: Float = 0.2

    /// Dominance threshold for confident/hesitant classification.
    static let emotionDominanceThreshold: Float = 0.3

    /// Arousal threshold for "animated" label.
    static let emotionAnimatedArousal: Float = 0.4

    // MARK: - Sentiment Trends (SentimentSummary)

    /// Valence delta threshold for improving/declining trend.
    static let trendDeltaThreshold: Float = 0.15

    /// Standard deviation threshold for "volatile" trend.
    static let trendVolatileStdDev: Float = 0.3

    // MARK: - Memory Extraction (ConversationMemory)

    /// Confidence above which a slot is considered "filled" and not overwritten.
    static let memoryHighConfidence: Float = 0.8

    /// Confidence for keyword-detected slots in current movement.
    static let memoryKeywordConfidence: Float = 0.6

    /// Confidence for cross-movement keyword detections (weaker signal).
    static let memoryCrossMovementConfidence: Float = 0.4

    // MARK: - Transcription Dedup

    /// Similarity threshold above which a segment is considered a duplicate.
    static let dedupSimilarityThreshold: Double = 0.85

    // MARK: - Suggestion Engine

    /// Minimum emotion confidence to show empathetic suggestion.
    static let suggestionMinConfidence: Float = 0.35

    /// Cooldown between suggestion changes (avoid flickering).
    static let suggestionCooldown: TimeInterval = 3.0
}
