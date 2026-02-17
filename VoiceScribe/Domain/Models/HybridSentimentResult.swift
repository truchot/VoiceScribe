import Foundation

// MARK: - Hybrid Sentiment Result (Value Object)

/// Result of merging prosodic, text-pattern, and semantic sentiment channels.
///
/// Lives in the Domain layer so that protocols and stores can reference it
/// without depending on the concrete `HybridSentiment` infrastructure class.
struct HybridSentimentResult {
    /// Merged emotional state (ready for SentimentStore)
    let emotion: EmotionalState

    /// Text signals that contributed (for coaching display)
    let textSignals: [CommercialTextSignal]

    /// Which source dominated this result
    let dominantSource: HybridSentimentSource

    /// Commercial alert (if strong text signal detected)
    let commercialAlert: CommercialAlert?
}

// MARK: - Hybrid Sentiment Source

/// Which analysis channel dominated the hybrid result.
enum HybridSentimentSource: String {
    case prosody       // Text was insignificant
    case textOverride  // Text was strong objection/signal overriding prosody
    case agreement     // Both prosody and text aligned
    case blended       // Weighted combination
}

// MARK: - Commercial Text Signal (Value Object)

/// Domain-level representation of a detected text signal.
///
/// Decouples the domain/application layers from the concrete
/// `TextSignalAnalyzer.DetectedSignal` infrastructure type.
struct CommercialTextSignal {
    let type: SignalKind
    let category: String
    let strength: Float
    let matchedPattern: String
    let textExcerpt: String

    enum SignalKind: String {
        case objection
        case buyingSignal
        case authorityFlag
        case competitorMention
        case urgencySignal
        case hesitation
        case engagement
        case disengagement
    }
}
