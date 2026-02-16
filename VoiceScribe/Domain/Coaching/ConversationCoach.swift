import Foundation

/// The unified coaching engine.
///
/// Combines all layers to produce ONE coherent advice output:
/// - Movement detection → where are we?
/// - Framework blueprint → what should we do here?
/// - Memory → what do we know? what's missing?
/// - Sentiment → how does the prospect feel?
/// - Empathetic coach → what to SAY for their emotion?
///
/// Output is a single `CoachingOutput` struct consumed by the UI.
final class ConversationCoach {
    
    // MARK: - Output
    
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
        let personalizedPhrase: String    // With memory substitutions
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
        let isReady: Bool       // Memory has enough for the transition
    }
    
    struct ActiveTip {
        let advice: String
        let alternatives: [String]
        let trigger: String     // Human-readable trigger description
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
    
    // MARK: - State
    
    private let detector = MovementDetector()
    private let memory = ConversationMemory()
    private let empatheticCoach = CoachingSuggestionEngine()
    
    private var lastDetection: MovementDetector.Detection?
    private var previousEmotion: EmotionLabel?
    private var tipCooldown: TimeInterval = 0
    
    var currentMovement: ConversationMovement { detector.currentMovement }
    var conversationMemory: ConversationMemory { memory }
    
    /// Setting the event bus wires it to both detector and memory.
    var eventBus: CoachingEventBus? {
        didSet {
            detector.eventBus = eventBus
            memory.eventBus = eventBus
        }
    }
    
    // MARK: - Public API
    
    /// Main coaching method — call after each new segment.
    func coach(
        recentSegments: ArraySlice<TranscriptionSegment>,
        allSegments: [TranscriptionSegment],
        emotion: EmotionalState,
        elapsed: TimeInterval
    ) -> CoachingOutput {
        
        // 1. Extract memory from new segments
        for segment in recentSegments.suffix(3) {
            memory.extract(from: segment, currentMovement: detector.currentMovement, elapsed: elapsed)
        }
        
        // 2. Detect movement
        let detection = detector.detect(
            recentSegments: recentSegments,
            allSegments: allSegments,
            emotion: emotion,
            memory: memory,
            elapsed: elapsed
        )
        lastDetection = detection
        
        // 3. Get blueprint
        let blueprint = ConversationFramework.blueprint(for: detection.currentMovement)
        
        // 4. Build focus statement
        let focus = buildFocus(blueprint: blueprint, detection: detection, emotion: emotion)
        
        // 5. Choose best action suggestion
        let action = chooseAction(blueprint: blueprint, detection: detection, emotion: emotion)
        
        // 6. Slot status
        let slotStatus = buildSlotStatus(for: detection.currentMovement)
        
        // 7. Transition nudge
        let nudge: TransitionNudge? = {
            guard detection.suggestTransition, let target = detection.transitionTarget else { return nil }
            let ready = memory.readiness(for: target)
            return TransitionNudge(target: target, reason: detection.transitionReason ?? "", isReady: ready > 0.5)
        }()
        
        // 8. Situational tip
        let tip = evaluateTips(blueprint: blueprint, detection: detection, emotion: emotion, elapsed: elapsed)
        
        // 9. Empathetic layer
        let emotionCoaching = buildEmotionCoaching(emotion: emotion, elapsed: elapsed)
        previousEmotion = emotion.label
        
        return CoachingOutput(
            movement: detection.currentMovement,
            act: detection.currentMovement.act,
            movementProgress: detection.movementProgress,
            timeInMovement: detection.timeInMovement,
            isManualOverride: detection.isManualOverride,
            goldenRule: blueprint.goldenRule,
            focusNow: focus,
            suggestedAction: action,
            memoryContext: memory.contextString(),
            slotStatus: slotStatus,
            readinessScore: memory.readiness(for: detection.currentMovement),
            speakerBalance: detection.speakerBalance,
            transitionNudge: nudge,
            activeTip: tip,
            fluidityScore: detection.fluidityScore,
            emotionCoaching: emotionCoaching
        )
    }
    
    /// Manual movement override
    func overrideMovement(_ movement: ConversationMovement, at elapsed: TimeInterval) {
        detector.override(to: movement, at: elapsed)
    }
    
    /// Manual memory entry
    func setMemory(key: String, value: String, elapsed: TimeInterval) {
        memory.set(key: key, value: value, movement: detector.currentMovement, elapsed: elapsed)
    }
    
    /// Generate post-call report
    func generateReport(elapsed: TimeInterval) -> PostCallReport {
        let memoryReport = memory.generateReport()
        let timeline = detector.timeline(currentElapsed: elapsed)
        
        return PostCallReport(
            totalDuration: elapsed,
            movementTimeline: timeline,
            memoryReport: memoryReport,
            movementCount: timeline.count,
            averageFluidityScore: lastDetection?.fluidityScore ?? 0,
            contextSummary: memory.contextString()
        )
    }
    
    func reset() {
        detector.reset()
        memory.reset()
        empatheticCoach.reset()
        lastDetection = nil
        previousEmotion = nil
        tipCooldown = 0
    }
    
    // MARK: - Build Focus
    
    private func buildFocus(
        blueprint: MovementBlueprint,
        detection: MovementDetector.Detection,
        emotion: EmotionalState
    ) -> String {
        let movement = detection.currentMovement
        
        // Check for missing critical info that blocks progress
        let missingCritical = memory.missingCriticalSlots(for: movement)
        if !missingCritical.isEmpty && detection.movementProgress > 0.5 {
            let names = missingCritical.prefix(2).map(\.label).joined(separator: ", ")
            return "Info manquante : \(names). Trouvez un moment naturel pour aborder ce point."
        }
        
        // Emotion-based override
        if movement == .proposition && (emotion.label == .disengaged || emotion.label == .neutral) {
            return "⚠️ Le prospect décroche. Arrêtez de présenter — posez une question."
        }
        if movement == .dialogue && emotion.label == .frustrated {
            return "⚠️ Frustration. Empathie d'abord, arguments après."
        }
        if emotion.label == .enthusiastic && movement.act == .solution {
            return "🟢 Signal d'achat. Le prospect est chaud — avancez vers l'engagement."
        }
        
        // Memory-enriched focus
        switch movement {
        case .enjeux:
            if !memory.has("main_pain") {
                return "Trouvez la douleur. Posez des questions ouvertes sur ce qui les ralentit au quotidien."
            }
            return "Douleur identifiée : \(memory.get("main_pain") ?? ""). Creusez les causes et le contexte."
            
        case .profondeur:
            if memory.has("main_pain") && !memory.has("pain_cost_time") {
                return "La douleur est \"\(memory.get("main_pain") ?? "")\". Quantifiez : combien ça leur coûte ?"
            }
            
        case .proposition:
            if memory.has("main_pain") && memory.has("desired_outcome") {
                return "Connectez votre solution à : \"\(memory.get("main_pain") ?? "")\" → \"\(memory.get("desired_outcome") ?? "")\"."
            }
            
        case .engagement:
            if memory.has("decision_maker") {
                let decider = memory.get("decision_maker") ?? ""
                return "Le décideur est \(decider). Votre proposition d'engagement doit l'inclure."
            }
            
        default:
            break
        }
        
        // Default: use blueprint intent (shortened)
        return blueprint.intent.components(separatedBy: ".").first ?? blueprint.intent
    }
    
    // MARK: - Choose Action
    
    private func chooseAction(
        blueprint: MovementBlueprint,
        detection: MovementDetector.Detection,
        emotion: EmotionalState
    ) -> ActionSuggestion {
        let openers = blueprint.openers
        
        // Pick best opener based on context
        let chosen: ConversationStarter
        
        // Emotion-driven choice
        if emotion.label == .hesitant || emotion.label == .frustrated {
            chosen = openers.first(where: { $0.energy == .empathetic }) ?? openers[0]
        } else if emotion.label == .confident || emotion.label == .enthusiastic {
            chosen = openers.first(where: { $0.energy == .direct }) ?? openers[0]
        } else if detection.movementProgress < CoachingThresholds.earlyProgressThreshold {
            // Early in movement: warm or curious
            chosen = openers.first(where: { $0.energy == .curious || $0.energy == .warm }) ?? openers[0]
        } else {
            // Later: direct or provocative
            chosen = openers.first(where: { $0.energy == .direct || $0.energy == .provocative })
                ?? openers[min(1, openers.count - 1)]
        }
        
        let alternatives = openers.filter { $0.phrase != chosen.phrase }.map(\.phrase)
        
        return ActionSuggestion(
            phrase: chosen.phrase,
            personalizedPhrase: memory.personalize(chosen.phrase),
            context: chosen.context,
            energy: chosen.energy,
            alternatives: alternatives,
            personalizedAlternatives: alternatives.map { memory.personalize($0) }
        )
    }
    
    // MARK: - Evaluate Tips
    
    private func evaluateTips(
        blueprint: MovementBlueprint,
        detection: MovementDetector.Detection,
        emotion: EmotionalState,
        elapsed: TimeInterval
    ) -> ActiveTip? {
        // Cooldown
        guard elapsed - tipCooldown > 10 else { return nil }
        
        for tip in blueprint.situationalTips {
            let triggered: Bool
            switch tip.trigger {
            case .emotionDetected(let target):
                triggered = emotion.label == target && emotion.confidence > CoachingThresholds.emotionCoachingMinConfidence
            case .tooLongInMovement:
                let (_, maxDur) = detection.currentMovement.expectedDuration
                triggered = detection.timeInMovement > maxDur
            case .tooShortInMovement:
                let (minDur, _) = detection.currentMovement.expectedDuration
                triggered = detection.timeInMovement < minDur && detection.suggestTransition
            case .speakingTooMuch:
                triggered = detection.speakerBalance.myRatio > detection.speakerBalance.idealRatio + CoachingThresholds.balanceTolerance
            case .speakingTooLittle:
                triggered = detection.speakerBalance.myRatio < detection.speakerBalance.idealRatio - CoachingThresholds.balanceTolerance
            case .silenceTooLong:
                triggered = false // TODO: implement silence tracking
            case .keywordDetected(let keyword):
                triggered = detection.signals.contains(keyword)
            case .memorySlotFilled(let key):
                if let slot = memory.slots[key] {
                    triggered = slot.timestamp > elapsed - 30
                } else { triggered = false }
            case .memorySlotMissing(let key):
                triggered = !memory.has(key) && detection.movementProgress > 0.6  // Could be added to thresholds if needed
            }
            
            if triggered {
                tipCooldown = elapsed
                let urgency: ActiveTip.TipUrgency = {
                    switch tip.trigger {
                    case .emotionDetected(.frustrated), .emotionDetected(.disengaged): return .action
                    case .tooLongInMovement, .speakingTooMuch: return .attention
                    default: return .info
                    }
                }()
                
                return ActiveTip(
                    advice: memory.personalize(tip.advice),
                    alternatives: tip.alternatives.map { memory.personalize($0) },
                    trigger: triggerDescription(tip.trigger),
                    urgency: urgency
                )
            }
        }
        
        return nil
    }
    
    private func buildSlotStatus(for movement: ConversationMovement) -> [SlotStatus] {
        let blueprint = ConversationFramework.blueprint(for: movement)
        return blueprint.memorySlots.map { slot in
            SlotStatus(
                key: slot.key,
                label: slot.label,
                importance: slot.importance,
                filled: memory.has(slot.key),
                value: memory.get(slot.key)
            )
        }
    }

    private func triggerDescription(_ trigger: SituationalTip.TipTrigger) -> String {
        switch trigger {
        case .emotionDetected(let e): return "Émotion: \(e.rawValue)"
        case .tooLongInMovement: return "Durée"
        case .tooShortInMovement: return "Trop court"
        case .speakingTooMuch: return "Balance parole"
        case .speakingTooLittle: return "Balance parole"
        case .silenceTooLong: return "Silence"
        case .keywordDetected(let k): return "Mot-clé: \(k)"
        case .memorySlotFilled(let k): return "Info captée: \(k)"
        case .memorySlotMissing(let k): return "Info manquante: \(k)"
        }
    }
    
    // MARK: - Emotion Coaching (Layer 2 integration)
    
    private func buildEmotionCoaching(emotion: EmotionalState, elapsed: TimeInterval) -> EmotionCoaching? {
        guard emotion.confidence > CoachingThresholds.emotionCoachingMinConfidence else { return nil }
        guard emotion.label != .neutral && emotion.label != .satisfied else { return nil }
        
        if let suggestion = empatheticCoach.suggest(
            emotion: emotion, previousEmotion: previousEmotion, timestamp: elapsed
        ) {
            return EmotionCoaching(
                emotion: emotion.label,
                emoji: emotion.label.emoji,
                empathyPhrase: suggestion.phrase,
                alternatives: suggestion.alternatives
            )
        }
        
        return nil
    }
}

// MARK: - Post-Call Report

// PostCallReport is in Domain/Models/PostCallReport.swift
