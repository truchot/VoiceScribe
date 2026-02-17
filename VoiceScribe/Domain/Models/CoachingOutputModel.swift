import Foundation

// MARK: - Coaching Output (Value Object)

/// Single coherent coaching advice produced by the coaching engine.
///
/// Standalone Domain type (previously nested in `ConversationCoach`).
/// This allows the protocol and all layers to reference the type without
/// depending on the concrete `ConversationCoach` class.
struct CoachingOutput {
    // Movement
    let movement: ConversationMovement
    let act: ConversationAct
    let movementProgress: Float
    let timeInMovement: TimeInterval
    let isManualOverride: Bool

    // Focus
    let goldenRule: String
    let focusNow: String

    // Action
    let suggestedAction: ActionSuggestion

    // Memory state
    let memoryContext: String
    let slotStatus: [SlotStatus]
    let readinessScore: Float

    // Balance
    let speakerBalance: MovementDetector.SpeakerBalance

    // Transition
    let transitionNudge: TransitionNudge?

    // Situational tip (if triggered)
    let activeTip: ActiveTip?

    // Fluidity
    let fluidityScore: Float

    // Empathetic layer
    let emotionCoaching: EmotionCoaching?
}

struct ActionSuggestion {
    let phrase: String
    let personalizedPhrase: String
    let context: String
    let energy: ConversationStarter.StarterEnergy
    let alternatives: [String]
    let personalizedAlternatives: [String]
}

struct SlotStatus {
    let key: String
    let label: String
    let importance: MemorySlot.SlotImportance
    let filled: Bool
    let value: String?
}

struct TransitionNudge {
    let target: ConversationMovement
    let reason: String
    let isReady: Bool
}

struct ActiveTip {
    let advice: String
    let alternatives: [String]
    let trigger: String
    let urgency: TipUrgency

    enum TipUrgency: String {
        case info = "Info"
        case attention = "Attention"
        case action = "Action"
    }
}

struct EmotionCoaching {
    let emotion: EmotionLabel
    let emoji: String
    let empathyPhrase: String
    let alternatives: [String]
}
