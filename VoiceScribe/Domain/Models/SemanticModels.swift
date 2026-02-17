import Foundation

// MARK: - Semantic Analysis (Value Object)

/// Result of deep text semantic analysis — intent, topics, and sentiment.
struct SemanticAnalysis {
    let sentiment: SemanticSentiment
    let topics: [DetectedTopic]
    let intent: ConversationalIntent
    let confidence: Float
    let timestamp: TimeInterval

    static func empty(at timestamp: TimeInterval) -> SemanticAnalysis {
        SemanticAnalysis(
            sentiment: SemanticSentiment(),
            topics: [],
            intent: .neutral,
            confidence: 0,
            timestamp: timestamp
        )
    }
}

// MARK: - Semantic Sentiment (Value Object)

/// Text-derived sentiment — complements prosodic analysis.
/// Immutable value object: create a new instance to change values.
struct SemanticSentiment: Equatable {
    /// Overall text polarity (-1.0 to 1.0)
    let polarity: Float
    /// Speaker certainty/conviction level (0 to 1)
    let certainty: Float
    /// Formality level (affects coaching tone suggestions)
    let formality: Float
    /// Engagement with the conversation topic (0 to 1)
    let engagement: Float

    init(polarity: Float = 0.0, certainty: Float = 0.5, formality: Float = 0.5, engagement: Float = 0.5) {
        self.polarity = max(-1.0, min(1.0, polarity))
        self.certainty = max(0, min(1, certainty))
        self.formality = max(0, min(1, formality))
        self.engagement = max(0, min(1, engagement))
    }

    var isPositive: Bool { polarity > 0.2 }
    var isNegative: Bool { polarity < -0.2 }
    var isNeutral: Bool { !isPositive && !isNegative }
}

// MARK: - Detected Topic (Entity)

/// A topic detected in the conversation, tracked over time.
struct DetectedTopic: Identifiable {
    let id: UUID
    let name: String
    let category: TopicCategory
    let confidence: Float
    let firstMentionTime: TimeInterval
    var mentionCount: Int

    init(name: String, category: TopicCategory, confidence: Float, timestamp: TimeInterval) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.confidence = confidence
        self.firstMentionTime = timestamp
        self.mentionCount = 1
    }

    mutating func incrementMention() {
        mentionCount += 1
    }
}

enum TopicCategory: String, Codable, CaseIterable {
    case pricing = "Prix"
    case timeline = "Délai"
    case competitor = "Concurrent"
    case technical = "Technique"
    case decision = "Décision"
    case pain = "Douleur"
    case success = "Succès"
    case general = "Général"
}

// MARK: - Conversational Intent (Value Object)

/// Detected intent of the speaker in a given segment.
enum ConversationalIntent: String, Codable, CaseIterable {
    case asking = "Question"
    case objecting = "Objection"
    case agreeing = "Accord"
    case requesting = "Demande"
    case clarifying = "Clarification"
    case committing = "Engagement"
    case deflecting = "Esquive"
    case neutral = "Neutre"

    var isPositive: Bool {
        switch self {
        case .agreeing, .committing, .asking: return true
        default: return false
        }
    }

    var isNegative: Bool {
        switch self {
        case .objecting, .deflecting: return true
        default: return false
        }
    }
}
