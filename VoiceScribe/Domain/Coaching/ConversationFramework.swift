import Foundation

// MARK: - The Conversation Framework
//
// A great sales call is a CONVERSATION, not an interrogation.
// The coach navigates between "movements" (not rigid phases) based
// on real-time dialogue signals — like jazz improvisation over structure.
//
// Blueprint data is loaded from Blueprints.json at startup.
// This allows non-developers to edit coaching content without touching code.

// MARK: - Movement Definition

enum ConversationMovement: Int, CaseIterable, Codable {
    case accueil = 0
    case cadrage = 1
    case univers = 2
    case enjeux = 3
    case profondeur = 4
    case vision = 5
    case qualification = 6
    case proposition = 7
    case dialogue = 8
    case engagement = 9
    case suivi = 10
    
    // MARK: - Identity
    
    var name: String {
        switch self {
        case .accueil: return "Accueil"
        case .cadrage: return "Cadrage"
        case .univers: return "Univers"
        case .enjeux: return "Enjeux"
        case .profondeur: return "Profondeur"
        case .vision: return "Vision"
        case .qualification: return "Qualification"
        case .proposition: return "Proposition"
        case .dialogue: return "Dialogue"
        case .engagement: return "Engagement"
        case .suivi: return "Suivi"
        }
    }
    
    var emoji: String {
        switch self {
        case .accueil: return "☕"
        case .cadrage: return "🗺️"
        case .univers: return "🌍"
        case .enjeux: return "🔍"
        case .profondeur: return "⛏️"
        case .vision: return "🌟"
        case .qualification: return "🧭"
        case .proposition: return "🎯"
        case .dialogue: return "💬"
        case .engagement: return "🤝"
        case .suivi: return "📬"
        }
    }
    
    var act: ConversationAct {
        switch self {
        case .accueil, .cadrage, .univers: return .connexion
        case .enjeux, .profondeur, .vision, .qualification: return .exploration
        case .proposition, .dialogue, .engagement: return .solution
        case .suivi: return .suivi
        }
    }
    
    var shortLabel: String {
        switch self {
        case .accueil: return "Accueil"
        case .cadrage: return "Cadre"
        case .univers: return "Univers"
        case .enjeux: return "Enjeux"
        case .profondeur: return "Impact"
        case .vision: return "Vision"
        case .qualification: return "Qualif"
        case .proposition: return "Offre"
        case .dialogue: return "Dialog"
        case .engagement: return "Action"
        case .suivi: return "Suivi"
        }
    }
    
    /// Ideal speaking ratio for the salesperson (0.0 = prospect talks, 1.0 = I talk)
    var idealMyRatio: Float {
        switch self {
        case .accueil: return 0.50
        case .cadrage: return 0.60
        case .univers: return 0.25
        case .enjeux: return 0.30
        case .profondeur: return 0.25
        case .vision: return 0.35
        case .qualification: return 0.45
        case .proposition: return 0.70
        case .dialogue: return 0.45
        case .engagement: return 0.55
        case .suivi: return 0.60
        }
    }
    
    /// Expected duration range (min, max) in seconds
    var expectedDuration: (min: TimeInterval, max: TimeInterval) {
        switch self {
        case .accueil: return (30, 180)
        case .cadrage: return (30, 120)
        case .univers: return (120, 480)
        case .enjeux: return (180, 600)
        case .profondeur: return (120, 420)
        case .vision: return (120, 360)
        case .qualification: return (60, 300)
        case .proposition: return (300, 720)
        case .dialogue: return (120, 600)
        case .engagement: return (60, 300)
        case .suivi: return (30, 120)
        }
    }
    
    var next: ConversationMovement? {
        ConversationMovement(rawValue: rawValue + 1)
    }
    var previous: ConversationMovement? {
        rawValue > 0 ? ConversationMovement(rawValue: rawValue - 1) : nil
    }
}

enum ConversationAct: String {
    case connexion = "Connexion"
    case exploration = "Exploration"
    case solution = "Solution"
    case suivi = "Suivi"
}

// MARK: - Blueprint Data Structures

struct MovementBlueprint {
    let movement: ConversationMovement
    let intent: String
    let prospectExperience: String
    let goldenRule: String
    let openers: [ConversationStarter]
    let memorySlots: [MemorySlot]
    let transitionCues: [String]
    let antiPatterns: [String]
    let situationalTips: [SituationalTip]
}

struct ConversationStarter: Codable {
    let phrase: String
    let context: String
    let energy: StarterEnergy
    
    enum StarterEnergy: String, Codable {
        case warm, curious, direct, empathetic, provocative
    }
}

struct MemorySlot: Codable {
    let key: String
    let label: String
    let importance: SlotImportance
    let detectionHints: [String]
    
    enum SlotImportance: String, Codable {
        case critical, important, helpful
    }
}

struct SituationalTip {
    let trigger: TipTrigger
    let advice: String
    let alternatives: [String]
    
    enum TipTrigger {
        case emotionDetected(EmotionLabel)
        case tooLongInMovement
        case tooShortInMovement
        case speakingTooMuch
        case speakingTooLittle
        case silenceTooLong
        case keywordDetected(String)
        case memorySlotFilled(String)
        case memorySlotMissing(String)
    }
}

// MARK: - JSON Intermediary (Codable bridge for TipTrigger)

private struct JSONBlueprint: Codable {
    let movement: String
    let intent: String
    let prospectExperience: String
    let goldenRule: String
    let openers: [ConversationStarter]
    let memorySlots: [MemorySlot]
    let transitionCues: [String]
    let antiPatterns: [String]
    let situationalTips: [JSONTip]
}

private struct JSONTip: Codable {
    let triggerType: String
    let triggerValue: String
    let advice: String
    let alternatives: [String]
    
    func toSituationalTip() -> SituationalTip? {
        let trigger: SituationalTip.TipTrigger
        switch triggerType {
        case "tooLongInMovement":   trigger = .tooLongInMovement
        case "tooShortInMovement":  trigger = .tooShortInMovement
        case "speakingTooMuch":     trigger = .speakingTooMuch
        case "speakingTooLittle":   trigger = .speakingTooLittle
        case "silenceTooLong":      trigger = .silenceTooLong
        case "keywordDetected":     trigger = .keywordDetected(triggerValue)
        case "memorySlotFilled":    trigger = .memorySlotFilled(triggerValue)
        case "memorySlotMissing":   trigger = .memorySlotMissing(triggerValue)
        case "emotionDetected":
            guard let label = EmotionLabel.allCases.first(where: {
                String(describing: $0).lowercased() == triggerValue.lowercased()
            }) else { return nil }
            trigger = .emotionDetected(label)
        default: return nil
        }
        return SituationalTip(trigger: trigger, advice: advice, alternatives: alternatives)
    }
}

// MARK: - Framework (JSON Loader)

struct ConversationFramework {
    
    /// Loaded blueprints, keyed by movement.
    private(set) static var blueprints: [ConversationMovement: MovementBlueprint] = loadBlueprints()
    
    /// Get blueprint for a movement.
    static func blueprint(for movement: ConversationMovement) -> MovementBlueprint {
        blueprints[movement] ?? fallback(for: movement)
    }
    
    /// All blueprints in movement order.
    static var orderedBlueprints: [MovementBlueprint] {
        ConversationMovement.allCases.compactMap { blueprints[$0] }
    }
    
    // MARK: - Loading
    
    private static func loadBlueprints() -> [ConversationMovement: MovementBlueprint] {
        guard let url = Bundle.main.url(forResource: "Blueprints", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let jsonBlueprints = try? JSONDecoder().decode([JSONBlueprint].self, from: data)
        else {
            Log.coaching.error("Failed to load Blueprints.json — using empty blueprints")
            return [:]
        }
        
        let movementMap: [String: ConversationMovement] = Dictionary(
            uniqueKeysWithValues: ConversationMovement.allCases.map {
                (String(describing: $0), $0)
            }
        )
        
        var result: [ConversationMovement: MovementBlueprint] = [:]
        for jb in jsonBlueprints {
            guard let movement = movementMap[jb.movement] else { continue }
            result[movement] = MovementBlueprint(
                movement: movement,
                intent: jb.intent,
                prospectExperience: jb.prospectExperience,
                goldenRule: jb.goldenRule,
                openers: jb.openers,
                memorySlots: jb.memorySlots,
                transitionCues: jb.transitionCues,
                antiPatterns: jb.antiPatterns,
                situationalTips: jb.situationalTips.compactMap { $0.toSituationalTip() }
            )
        }
        
        Log.coaching.info("Loaded \(result.count) movement blueprints from JSON")
        return result
    }
    
    /// Minimal fallback if JSON loading fails.
    private static func fallback(for movement: ConversationMovement) -> MovementBlueprint {
        MovementBlueprint(
            movement: movement, intent: "—", prospectExperience: "—", goldenRule: "—",
            openers: [], memorySlots: [], transitionCues: [], antiPatterns: [], situationalTips: []
        )
    }
}
