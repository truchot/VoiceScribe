import Foundation

/// Detects the current conversation movement based on transcript signals,
/// sentiment, timing, and memory state.
///
/// Unlike rigid phase detection, this system:
/// - Allows non-linear movement (jump back/forward)
/// - Treats manual overrides as permanent anchors
/// - Uses memory completeness to suggest transitions
/// - Keeps a "fluidity score" (how natural the conversation feels)
final class MovementDetector {
    
    // MARK: - Detection Result
    
    struct Detection {
        let currentMovement: ConversationMovement
        let confidence: Float
        let signals: [String]
        let timeInMovement: TimeInterval
        let movementProgress: Float        // 0.0 - 1.0 based on duration vs expected
        let suggestTransition: Bool
        let transitionTarget: ConversationMovement?
        let transitionReason: String?
        let speakerBalance: SpeakerBalance
        let fluidityScore: Float           // How natural the conversation feels (0-1)
        let isManualOverride: Bool
    }
    
    struct SpeakerBalance {
        let myRatio: Float          // 0.0 - 1.0
        let idealRatio: Float
        let isHealthy: Bool
        let advice: String?
    }
    
    // MARK: - State
    
    private(set) var currentMovement: ConversationMovement = .accueil
    private var movementStartTime: TimeInterval = 0
    private var movementHistory: [(movement: ConversationMovement, start: TimeInterval, end: TimeInterval)] = []
    private var isOverridden = false
    
    // Domain events
    var eventBus: CoachingEventBus?
    
    // Speaker tracking (incremental — only count new segments)
    private var myWordCount: Int = 0
    private var otherWordCount: Int = 0
    private var recentMyWords: Int = 0       // Based on recentSegments window
    private var recentOtherWords: Int = 0
    
    /// Pre-allocated scoring storage. Reused each detect() call to avoid
    /// dictionary + array allocations on the hot path.
    private var scoreValues: [Float] = [Float](repeating: 0, count: ConversationMovement.allCases.count)
    private var scoreSignals: [[String]] = Array(repeating: [], count: ConversationMovement.allCases.count)
    private var processedSegmentCount: Int = 0  // How many segments have been counted into totals
    
    // Keyword patterns per movement (subset — most detection comes from memory)
    private let signalPatterns: [ConversationMovement: [(String, Float)]] = [
        .accueil: [
            ("bonjour", 1.0), ("enchanté", 1.0), ("ravi", 0.8), ("comment allez", 0.8),
            ("comment ça va", 0.7), ("merci d'avoir pris", 0.9), ("bienvenue", 0.7)
        ],
        .cadrage: [
            ("agenda", 0.8), ("objectif de cet appel", 1.0), ("je vous propose", 0.7),
            ("ça vous va", 0.9), ("comment on procède", 0.8), ("déroulé", 0.8)
        ],
        .univers: [
            ("votre entreprise", 0.7), ("votre équipe", 0.7), ("au quotidien", 0.8),
            ("process", 0.6), ("outil", 0.6), ("organisation", 0.7), ("combien êtes-vous", 0.8)
        ],
        .enjeux: [
            ("problème", 0.8), ("difficulté", 0.8), ("challenge", 0.9), ("galère", 0.9),
            ("frustrant", 1.0), ("bloqué", 0.8), ("qu'est-ce qui vous empêche", 1.0)
        ],
        .profondeur: [
            ("combien ça coûte", 1.0), ("temps perdu", 1.0), ("impact", 0.9),
            ("conséquence", 0.8), ("si on ne fait rien", 1.0), ("chiffre", 0.6)
        ],
        .vision: [
            ("idéal", 0.9), ("dans 6 mois", 0.9), ("si c'était résolu", 1.0),
            ("rêve", 0.7), ("objectif", 0.6), ("succès", 0.8)
        ],
        .qualification: [
            ("budget", 1.0), ("décideur", 1.0), ("qui décide", 1.0), ("timeline", 0.9),
            ("deadline", 0.9), ("quand", 0.5), ("processus de décision", 1.0),
            ("validation", 0.7), ("comité", 0.8)
        ],
        .proposition: [
            ("je vous montre", 1.0), ("voici comment", 0.9), ("notre solution", 0.8),
            ("concrètement", 0.6), ("démo", 1.0), ("cas client", 0.8)
        ],
        .dialogue: [
            ("trop cher", 1.0), ("réfléchir", 0.9), ("pas sûr", 0.9), ("concurrent", 0.8),
            ("risque", 0.7), ("garantie", 0.8), ("oui mais", 0.9), ("inquiétude", 0.9)
        ],
        .engagement: [
            ("prochaine étape", 1.0), ("on avance", 1.0), ("signer", 0.9),
            ("contrat", 0.9), ("démarrer", 0.8), ("quand commence", 1.0)
        ],
        .suivi: [
            ("récap", 0.9), ("résumé", 0.8), ("compte-rendu", 1.0),
            ("je vous envoie", 0.8), ("prochain rendez-vous", 1.0), ("à bientôt", 0.7)
        ]
    ]
    
    // MARK: - Public API
    
    /// Analyze conversation state and detect current movement.
    func detect(
        recentSegments: ArraySlice<TranscriptionSegment>,
        allSegments: [TranscriptionSegment],
        emotion: EmotionalState,
        memory: ConversationMemory,
        elapsed: TimeInterval
    ) -> Detection {
        
        updateSpeakerStats(allSegments, recentSegments: recentSegments)
        
        let recentText = recentSegments.map { $0.text.lowercased() }.joined(separator: " ")
        
        // Reset pre-allocated scoring arrays (no allocation)
        for i in 0..<scoreValues.count {
            scoreValues[i] = 0
            scoreSignals[i].removeAll(keepingCapacity: true)
        }
        
        // Helper: indexed score mutation (no dictionary overhead)
        func addScore(_ m: ConversationMovement, _ delta: Float, signal: String? = nil) {
            scoreValues[m.rawValue] += delta
            if let sig = signal { scoreSignals[m.rawValue].append(sig) }
        }
        func mulScore(_ m: ConversationMovement, _ factor: Float) {
            scoreValues[m.rawValue] *= factor
        }
        
        // 1. Keyword signals
        for (movement, patterns) in signalPatterns {
            for (pattern, weight) in patterns {
                if recentText.contains(pattern) {
                    addScore(movement, weight, signal: pattern)
                }
            }
        }
        
        // 2. Memory-based signals (most powerful)
        // If memory slots for a movement are getting filled, we're probably there
        for m in ConversationMovement.allCases {
            let bp = ConversationFramework.blueprint(for: m)
            let recentlyFilled = bp.memorySlots.filter { slot in
                if let captured = memory.slots[slot.key] {
                    return captured.timestamp > elapsed - CoachingThresholds.recentSlotWindow
                }
                return false
            }
            if !recentlyFilled.isEmpty {
                addScore(m, Float(recentlyFilled.count) * CoachingThresholds.memorySlotWeight,
                         signal: "\(recentlyFilled.count) slots remplis")
            }
        }
        
        // 3. Temporal bias
        let minutes = Float(elapsed / 60.0)
        for m in ConversationMovement.allCases {
            let (_, maxDur) = m.expectedDuration
            let maxMin = Float(maxDur / 60.0)
            let cumMin = cumulativeMinutes(upTo: m)
            
            if minutes >= cumMin - 2 && minutes <= cumMin + maxMin {
                addScore(m, CoachingThresholds.temporalBiasBonus)
            }
        }
        
        // 4. Continuity (stay in current movement unless strong signal to change)
        addScore(currentMovement, CoachingThresholds.continuityBonus)
        
        // 5. Forward bias (penalize going backward, but don't prevent it)
        for m in ConversationMovement.allCases {
            if m.rawValue < currentMovement.rawValue {
                mulScore(m, CoachingThresholds.backwardPenalty)
            }
        }
        
        // 6. Emotion signals
        if emotion.label == .frustrated || emotion.label == .hesitant {
            addScore(.dialogue, CoachingThresholds.emotionDialogueBonus,
                     signal: "émotion: \(emotion.label.rawValue)")
        }
        if emotion.label == .enthusiastic || emotion.label == .confident {
            addScore(.engagement, CoachingThresholds.emotionEngagementBonus,
                     signal: "émotion: \(emotion.label.rawValue)")
        }
        
        // Find best movement (indexed array scan — no dictionary overhead)
        var bestIdx = 0
        var bestScore: Float = scoreValues[0]
        var totalScore: Float = scoreValues[0]
        for i in 1..<scoreValues.count {
            totalScore += scoreValues[i]
            if scoreValues[i] > bestScore {
                bestScore = scoreValues[i]
                bestIdx = i
            }
        }
        guard let bestMovement = ConversationMovement(rawValue: bestIdx) else {
            return Detection(
                currentMovement: currentMovement, confidence: 0, signals: [],
                timeInMovement: elapsed - movementStartTime, movementProgress: 0,
                suggestTransition: false, transitionTarget: nil, transitionReason: nil,
                speakerBalance: computeBalance(), fluidityScore: CoachingThresholds.fluidityBase,
                isManualOverride: isOverridden
            )
        }
        let confidence: Float = totalScore > 0 ? bestScore / totalScore : 0
        
        // Only switch if strong signal (unless manual override active)
        if !isOverridden && bestMovement != currentMovement && confidence > CoachingThresholds.movementSwitchConfidence && bestScore > CoachingThresholds.movementSwitchMinScore {
            let previous = currentMovement
            movementHistory.append((movement: currentMovement, start: movementStartTime, end: elapsed))
            currentMovement = bestMovement
            movementStartTime = elapsed
            eventBus?.emit(.movementChanged(from: previous, to: bestMovement, elapsed: elapsed, isManualOverride: false))
        }
        
        // Reset override flag (it only blocks one detection cycle after a manual switch)
        // Actually, we keep it sticky until auto-detection naturally arrives at the overridden movement
        
        // Time in current movement
        let timeInMovement = elapsed - movementStartTime
        let (_, maxDur) = currentMovement.expectedDuration
        let progress = min(1.0, Float(timeInMovement / maxDur))
        
        // Transition suggestion
        let (suggestTransition, target, reason) = evaluateTransition(
            memory: memory, elapsed: elapsed, timeInMovement: timeInMovement, emotion: emotion
        )
        
        // Speaker balance
        let balance = computeBalance()
        
        // Fluidity score
        let fluidity = computeFluidity(timeInMovement: timeInMovement, balance: balance, memory: memory)
        
        return Detection(
            currentMovement: currentMovement,
            confidence: confidence,
            signals: scoreSignals[bestIdx],
            timeInMovement: timeInMovement,
            movementProgress: progress,
            suggestTransition: suggestTransition,
            transitionTarget: target,
            transitionReason: reason,
            speakerBalance: balance,
            fluidityScore: fluidity,
            isManualOverride: isOverridden
        )
    }
    
    /// Manual override — user clicks on a movement.
    /// This is PERMANENT: the coach adapts all downstream behavior.
    func override(to movement: ConversationMovement, at elapsed: TimeInterval) {
        let previous = currentMovement
        movementHistory.append((movement: currentMovement, start: movementStartTime, end: elapsed))
        currentMovement = movement
        movementStartTime = elapsed
        isOverridden = true
        eventBus?.emit(.movementChanged(from: previous, to: movement, elapsed: elapsed, isManualOverride: true))
    }
    
    /// Get the complete movement timeline for post-call report
    func timeline(currentElapsed: TimeInterval) -> [(movement: ConversationMovement, start: TimeInterval, end: TimeInterval)] {
        var result = movementHistory
        result.append((movement: currentMovement, start: movementStartTime, end: currentElapsed))
        return result
    }
    
    func reset() {
        currentMovement = .accueil
        movementStartTime = 0
        movementHistory.removeAll()
        isOverridden = false
        myWordCount = 0; otherWordCount = 0
        recentMyWords = 0; recentOtherWords = 0
        processedSegmentCount = 0
    }
    
    // MARK: - Transition Logic
    
    private func evaluateTransition(
        memory: ConversationMemory,
        elapsed: TimeInterval,
        timeInMovement: TimeInterval,
        emotion: EmotionalState
    ) -> (suggest: Bool, target: ConversationMovement?, reason: String?) {
        
        let (_, maxDur) = currentMovement.expectedDuration
        let overtimeRatio = timeInMovement / maxDur
        
        // Don't suggest transition too early
        guard overtimeRatio > CoachingThresholds.transitionSuggestRatio else { return (false, nil, nil) }
        
        // Movement-specific transition logic
        switch currentMovement {
            
        case .accueil:
            // Always suggest moving to cadrage after ~2 min
            if timeInMovement > 120 {
                return (true, .cadrage, "Le lien est créé — posez le cadre de la conversation.")
            }
            
        case .cadrage:
            if memory.has("initial_agreement") {
                return (true, .univers, "Accord obtenu ✓ Explorez leur univers.")
            }
            if timeInMovement > 120 {
                return (true, .univers, "Passez à la découverte de leur contexte.")
            }
            
        case .univers:
            let hasContext = memory.has("company_name") || memory.has("current_process") || memory.has("team_structure")
            if hasContext && timeInMovement > 180 {
                return (true, .enjeux, "Vous avez le contexte — creusez les enjeux.")
            }
            
        case .enjeux:
            if memory.has("main_pain") {
                return (true, .profondeur, "Douleur identifiée ✓ Quantifiez l'impact.")
            }
            if timeInMovement > 480 {
                return (true, .profondeur, "Passez à l'impact — même si la douleur n'est pas encore claire, l'approfondissement aidera.")
            }
            
        case .profondeur:
            let hasCost = memory.has("pain_cost_time") || memory.has("pain_cost_money")
            if hasCost {
                return (true, .vision, "Impact chiffré ✓ Faites-les visualiser la solution.")
            }
            
        case .vision:
            if memory.has("desired_outcome") {
                let qualReady = memory.readiness(for: .qualification)
                if qualReady < 0.5 {
                    return (true, .qualification, "Vision posée ✓ Qualifiez maintenant (budget, timing, décideur).")
                }
                return (true, .proposition, "Vision + Qualification OK — présentez votre offre.")
            }
            
        case .qualification:
            let score = memory.readiness(for: .proposition)
            if score > 0.7 {
                return (true, .proposition, "Qualifié ✓ Vous pouvez présenter.")
            }
            
        case .proposition:
            if emotion.label == .hesitant || emotion.label == .frustrated {
                return (true, .dialogue, "Objections détectées — passez en mode dialogue.")
            }
            if timeInMovement > 600 {
                return (true, .dialogue, "Présentation longue — ouvrez la discussion.")
            }
            
        case .dialogue:
            if memory.has("objections_resolved") || emotion.label == .confident {
                return (true, .engagement, "Objections traitées — engagez.")
            }
            
        case .engagement:
            if memory.has("next_step_date") || memory.has("commitment_type") {
                return (true, .suivi, "Engagement obtenu ✓ Récapitulez.")
            }
            
        case .suivi:
            return (false, nil, nil)
        }
        
        // Generic: too long in any movement
        if overtimeRatio > CoachingThresholds.overtimeForceRatio, let next = currentMovement.next {
            return (true, next, "Vous êtes sur ce mouvement depuis longtemps. Pensez à avancer.")
        }
        
        return (false, nil, nil)
    }
    
    // MARK: - Speaker Balance
    
    private func computeBalance() -> SpeakerBalance {
        let totalRecent = recentMyWords + recentOtherWords
        let myRatio: Float = totalRecent > 0 ? Float(recentMyWords) / Float(totalRecent) : 0.5
        let idealRatio = currentMovement.idealMyRatio
        let diff = myRatio - idealRatio
        let tolerance = CoachingThresholds.balanceTolerance
        let isHealthy = abs(diff) < tolerance
        
        var advice: String? = nil
        if !isHealthy {
            if diff > tolerance {
                advice = "Vous parlez trop — posez une question ouverte et écoutez."
            } else if diff < -tolerance && currentMovement == .proposition {
                advice = "C'est le moment de présenter — reprenez la parole avec structure."
            } else if diff < -tolerance {
                advice = "Le prospect parle beaucoup — c'est bien ! Guidez avec des relances."
            }
        }
        
        return SpeakerBalance(myRatio: myRatio, idealRatio: idealRatio, isHealthy: isHealthy, advice: advice)
    }
    
    private func computeFluidity(
        timeInMovement: TimeInterval,
        balance: SpeakerBalance,
        memory: ConversationMemory
    ) -> Float {
        var score = CoachingThresholds.fluidityBase
        
        // Penalty for bad balance
        if !balance.isHealthy { score -= CoachingThresholds.fluidityBalancePenalty }
        
        // Penalty for being too long in a movement
        let (_, maxDur) = currentMovement.expectedDuration
        if timeInMovement > maxDur * CoachingThresholds.overtimeForceRatio { score -= CoachingThresholds.fluidityOvertimePenalty }
        
        // Bonus for having filled memory slots
        let readiness = memory.readiness(for: currentMovement)
        score += readiness * CoachingThresholds.fluidityMemoryBonus
        
        // Penalty for too many movement switches (chaotic)
        if movementHistory.count > CoachingThresholds.fluidityMaxMovements { score -= CoachingThresholds.fluidityChaotisPenalty }
        
        return min(1.0, max(0.0, score))
    }
    
    /// Incremental speaker stats: O(new segments) for totals, O(recent window) for balance.
    /// Called every ~500ms. Before: O(all segments) × 4 passes. After: O(k) where k ≈ 1 new segment.
    private func updateSpeakerStats(_ all: [TranscriptionSegment], recentSegments: ArraySlice<TranscriptionSegment>) {
        // Incremental totals: only count segments we haven't seen yet
        let newSegments = all.dropFirst(processedSegmentCount)
        for segment in newSegments {
            let words = segment.text.split(separator: " ").count
            switch segment.speaker {
            case .me:      myWordCount += words
            case .other:   otherWordCount += words
            case .unknown: break
            }
        }
        processedSegmentCount = all.count

        // Recent window: always recount (capped at ~20 segments — constant cost)
        recentMyWords = 0
        recentOtherWords = 0
        for segment in recentSegments {
            let words = segment.text.split(separator: " ").count
            switch segment.speaker {
            case .me:      recentMyWords += words
            case .other:   recentOtherWords += words
            case .unknown: break
            }
        }
    }
    
    /// Cumulative expected minutes to reach a movement
    private func cumulativeMinutes(upTo movement: ConversationMovement) -> Float {
        var total: Float = 0
        for m in ConversationMovement.allCases {
            if m.rawValue >= movement.rawValue { break }
            let (minDur, maxDur) = m.expectedDuration
            total += Float((minDur + maxDur) / 2.0 / 60.0)
        }
        return total
    }
}
