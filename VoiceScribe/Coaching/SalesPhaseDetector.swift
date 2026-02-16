import Foundation

/// Detects the current sales call phase from conversation signals.
///
/// Phases follow a natural commercial flow:
/// OUVERTURE → DÉCOUVERTE → QUALIFICATION → PRÉSENTATION → OBJECTIONS → CLOSING → SUIVI
///
/// Detection uses a scoring system based on:
/// - Keyword patterns in recent transcript
/// - Speaker balance (who talks more)
/// - Question density
/// - Sentiment trends
/// - Time elapsed
final class SalesPhaseDetector {
    
    // MARK: - Sales Phases
    
    enum SalesPhase: String, CaseIterable, Codable {
        case ouverture = "Ouverture"
        case decouverte = "Découverte"
        case qualification = "Qualification"
        case presentation = "Présentation"
        case objections = "Objections"
        case closing = "Closing"
        case suivi = "Suivi / Next Steps"
        
        var icon: String {
            switch self {
            case .ouverture: return "hand.wave"
            case .decouverte: return "magnifyingglass"
            case .qualification: return "checklist"
            case .presentation: return "theatermasks"
            case .objections: return "shield"
            case .closing: return "handshake"
            case .suivi: return "arrow.right.circle"
            }
        }
        
        var emoji: String {
            switch self {
            case .ouverture: return "👋"
            case .decouverte: return "🔍"
            case .qualification: return "✅"
            case .presentation: return "🎯"
            case .objections: return "🛡️"
            case .closing: return "🤝"
            case .suivi: return "📋"
            }
        }
        
        var color: String {
            switch self {
            case .ouverture: return "cyan"
            case .decouverte: return "blue"
            case .qualification: return "indigo"
            case .presentation: return "purple"
            case .objections: return "orange"
            case .closing: return "green"
            case .suivi: return "mint"
            }
        }
        
        /// Natural next phase
        var next: SalesPhase? {
            switch self {
            case .ouverture: return .decouverte
            case .decouverte: return .qualification
            case .qualification: return .presentation
            case .presentation: return .objections
            case .objections: return .closing
            case .closing: return .suivi
            case .suivi: return nil
            }
        }
        
        /// Ideal speaker balance (how much the prospect should talk, 0.0-1.0)
        var idealProspectRatio: Float {
            switch self {
            case .ouverture: return 0.5
            case .decouverte: return 0.7     // Prospect talks most
            case .qualification: return 0.6
            case .presentation: return 0.3   // We talk most
            case .objections: return 0.5
            case .closing: return 0.4
            case .suivi: return 0.5
            }
        }
    }
    
    // MARK: - Phase Score
    
    struct PhaseScore {
        let phase: SalesPhase
        var score: Float = 0
        var signals: [String] = []
    }
    
    // MARK: - Detection Result
    
    struct DetectionResult {
        let currentPhase: SalesPhase
        let confidence: Float
        let signals: [String]
        let speakerBalance: Float        // 0.0 (all me) to 1.0 (all prospect)
        let balanceAdvice: String?        // nil if balance is good
        let phaseProgress: Float          // 0.0 to 1.0 within current phase
        let suggestTransition: Bool       // Should we move to next phase?
        let transitionReason: String?
    }
    
    // MARK: - Keyword Patterns
    
    /// Keywords that signal each phase. Weighted by strength.
    private let phaseSignals: [SalesPhase: [(pattern: String, weight: Float)]] = [
        .ouverture: [
            ("bonjour", 1.0), ("enchanté", 1.0), ("ravi", 0.8), ("comment allez", 0.8),
            ("merci d'avoir pris", 0.9), ("merci pour votre temps", 0.9),
            ("on s'était parlé", 0.7), ("agenda", 0.6), ("objectif de cet appel", 0.9),
            ("order du jour", 0.8), ("comment ça va", 0.7), ("bienvenue", 0.8)
        ],
        .decouverte: [
            ("quel est votre", 1.0), ("comment vous", 0.8), ("parlez-moi de", 1.0),
            ("quelle est votre situation", 1.0), ("aujourd'hui comment", 0.9),
            ("quels sont vos", 1.0), ("qu'est-ce qui", 0.9), ("pouvez-vous me décrire", 1.0),
            ("quel est le challenge", 1.0), ("d'où venez-vous", 0.7),
            ("votre processus actuel", 0.9), ("combien de temps", 0.8),
            ("quelle est la difficulté", 1.0), ("impact sur", 0.8),
            ("si je comprends bien", 0.7), ("c'est-à-dire", 0.6),
            ("concrètement", 0.7), ("par exemple", 0.6)
        ],
        .qualification: [
            ("budget", 1.0), ("décideur", 1.0), ("qui décide", 1.0),
            ("timeline", 0.9), ("échéance", 0.9), ("deadline", 0.9),
            ("quand souhaitez", 0.9), ("priorité", 0.8), ("urgent", 0.8),
            ("combien êtes-vous", 0.7), ("taille de l'équipe", 0.8),
            ("avez-vous déjà essayé", 0.9), ("autres solutions", 0.9),
            ("concurrent", 0.8), ("comparé", 0.7), ("critères", 0.9),
            ("processus de décision", 1.0), ("validation", 0.8),
            ("comité", 0.7), ("stakeholder", 0.8), ("ROI", 0.9),
            ("retour sur investissement", 0.9), ("KPI", 0.8)
        ],
        .presentation: [
            ("je vous propose", 1.0), ("notre solution", 1.0), ("voici comment", 0.9),
            ("laissez-moi vous montrer", 1.0), ("concrètement on fait", 0.9),
            ("la différence c'est", 0.9), ("ce qui nous distingue", 1.0),
            ("par rapport à votre besoin", 0.9), ("cas client", 0.8),
            ("résultat", 0.8), ("témoignage", 0.7), ("démo", 1.0),
            ("fonctionnalité", 0.8), ("avantage", 0.8), ("bénéfice", 0.9),
            ("valeur ajoutée", 0.9), ("on a aidé", 0.8), ("exemple concret", 0.8)
        ],
        .objections: [
            ("trop cher", 1.0), ("c'est cher", 1.0), ("le prix", 0.9),
            ("je dois réfléchir", 1.0), ("j'ai besoin de temps", 1.0),
            ("je ne suis pas sûr", 0.9), ("on a déjà", 0.8), ("pas le bon moment", 1.0),
            ("notre prestataire actuel", 0.9), ("par rapport à", 0.7),
            ("compliqué", 0.8), ("complexe", 0.7), ("risque", 0.8),
            ("garantie", 0.8), ("mais", 0.4), ("cependant", 0.5),
            ("oui mais", 0.9), ("le problème c'est", 0.8),
            ("mon boss", 0.7), ("ma direction", 0.7), ("convaincre en interne", 0.9),
            ("pas convaincu", 1.0), ("qu'est-ce qui se passe si", 0.8)
        ],
        .closing: [
            ("on commence quand", 1.0), ("prochaine étape", 1.0),
            ("comment on avance", 1.0), ("signer", 0.9), ("contrat", 0.9),
            ("démarrer", 0.9), ("go", 0.7), ("on y va", 0.9),
            ("c'est bon pour moi", 1.0), ("je suis partant", 1.0),
            ("envoyez-moi", 0.8), ("proposition", 0.8), ("devis", 0.9),
            ("facturation", 0.8), ("onboarding", 0.9), ("planning", 0.7),
            ("d'accord", 0.5), ("ok parfait", 0.6), ("deal", 0.8)
        ],
        .suivi: [
            ("récap", 0.9), ("résumé", 0.9), ("compte-rendu", 1.0),
            ("je vous envoie", 0.9), ("prochain rendez-vous", 1.0),
            ("la suite", 0.8), ("d'ici là", 0.7), ("à bientôt", 0.8),
            ("merci pour cet échange", 0.9), ("bonne continuation", 0.7),
            ("on se redit", 0.8), ("on cale", 0.8), ("action", 0.7)
        ]
    ]
    
    // MARK: - State
    
    private(set) var currentPhase: SalesPhase = .ouverture
    private var phaseStartTime: TimeInterval = 0
    private var phaseHistory: [(phase: SalesPhase, timestamp: TimeInterval)] = []
    private var lastDetection: DetectionResult?
    
    // Running counters
    private var mySegmentCount: Int = 0
    private var otherSegmentCount: Int = 0
    private var myWordCount: Int = 0
    private var otherWordCount: Int = 0
    
    // MARK: - Public API
    
    /// Analyze recent segments and determine the current phase.
    /// Call this after each new segment.
    func detect(
        recentSegments: [TranscriptionSegment],
        allSegments: [TranscriptionSegment],
        currentEmotion: EmotionalState,
        elapsedTime: TimeInterval
    ) -> DetectionResult {
        
        // Update speaker counters
        updateSpeakerStats(allSegments)
        
        // Score each phase
        var scores = SalesPhase.allCases.map { PhaseScore(phase: $0) }
        
        // 1. Keyword scoring on recent segments (last ~2 minutes)
        let recentText = recentSegments.map { $0.text.lowercased() }.joined(separator: " ")
        
        for i in 0..<scores.count {
            let phase = scores[i].phase
            if let patterns = phaseSignals[phase] {
                for (pattern, weight) in patterns {
                    if recentText.contains(pattern) {
                        scores[i].score += weight
                        scores[i].signals.append(pattern)
                    }
                }
            }
        }
        
        // 2. Temporal bias (early = ouverture, later phases more likely over time)
        let minutesElapsed = Float(elapsedTime / 60.0)
        scores[0].score += max(0, 2.0 - minutesElapsed)    // Ouverture: first 2 min
        scores[1].score += minutesElapsed > 1 ? 0.5 : 0     // Découverte: after 1 min
        scores[2].score += minutesElapsed > 5 ? 0.5 : 0     // Qualification: after 5 min
        scores[3].score += minutesElapsed > 10 ? 0.5 : 0    // Présentation: after 10 min
        scores[4].score += minutesElapsed > 15 ? 0.3 : 0    // Objections: after 15 min
        scores[5].score += minutesElapsed > 20 ? 0.3 : 0    // Closing: after 20 min
        
        // 3. Phase continuity bias (sticky — don't switch too easily)
        if let idx = scores.firstIndex(where: { $0.phase == currentPhase }) {
            scores[idx].score += 1.5
        }
        
        // 4. Forward-only bias (don't go backwards usually)
        if let currentIdx = SalesPhase.allCases.firstIndex(of: currentPhase) {
            for i in 0..<currentIdx {
                scores[i].score *= 0.3  // Penalize going backward
            }
        }
        
        // 5. Emotion-based signals
        if currentEmotion.label == .hesitant || currentEmotion.label == .frustrated {
            if let idx = scores.firstIndex(where: { $0.phase == .objections }) {
                scores[idx].score += 0.8
                scores[idx].signals.append("émotion: \(currentEmotion.label.rawValue)")
            }
        }
        if currentEmotion.label == .enthusiastic || currentEmotion.label == .confident {
            if let idx = scores.firstIndex(where: { $0.phase == .closing }) {
                scores[idx].score += 0.5
                scores[idx].signals.append("émotion: \(currentEmotion.label.rawValue)")
            }
        }
        
        // Find winner
        let best = scores.max(by: { $0.score < $1.score })!
        let totalScore = scores.map(\.score).reduce(0, +)
        let confidence = totalScore > 0 ? best.score / totalScore : 0
        
        // Phase transition
        if best.phase != currentPhase && confidence > 0.35 {
            phaseHistory.append((phase: currentPhase, timestamp: elapsedTime))
            currentPhase = best.phase
            phaseStartTime = elapsedTime
        }
        
        // Speaker balance
        let totalWords = myWordCount + otherWordCount
        let prospectRatio: Float = totalWords > 0 ? Float(otherWordCount) / Float(totalWords) : 0.5
        let idealRatio = currentPhase.idealProspectRatio
        let balanceDiff = prospectRatio - idealRatio
        
        var balanceAdvice: String? = nil
        if abs(balanceDiff) > 0.15 {
            if balanceDiff < -0.15 {
                balanceAdvice = "Laissez plus de place au prospect — posez des questions ouvertes"
            } else if balanceDiff > 0.15 && currentPhase == .presentation {
                balanceAdvice = "C'est le moment de présenter — reprenez la parole"
            }
        }
        
        // Phase progress estimate
        let timeInPhase = Float(elapsedTime - phaseStartTime)
        let expectedDuration: Float = {
            switch currentPhase {
            case .ouverture: return 120     // 2 min
            case .decouverte: return 600    // 10 min
            case .qualification: return 300 // 5 min
            case .presentation: return 600  // 10 min
            case .objections: return 300    // 5 min
            case .closing: return 180       // 3 min
            case .suivi: return 120         // 2 min
            }
        }()
        let progress = min(1.0, timeInPhase / expectedDuration)
        
        // Transition suggestion
        var suggestTransition = false
        var transitionReason: String? = nil
        
        if progress > 0.8 && currentPhase.next != nil {
            suggestTransition = true
            switch currentPhase {
            case .ouverture:
                transitionReason = "L'ouverture est faite — passez aux questions de découverte"
            case .decouverte:
                transitionReason = "Vous avez assez de contexte — qualifiez le besoin"
            case .qualification:
                transitionReason = "Budget/timing/décideur identifiés — présentez votre offre"
            case .presentation:
                transitionReason = "Présentation terminée — attendez-vous aux objections"
            case .objections:
                transitionReason = "Objections traitées — tentez le closing"
            case .closing:
                transitionReason = "Deal conclu ou en bonne voie — définissez les prochaines étapes"
            case .suivi:
                transitionReason = nil
                suggestTransition = false
            }
        }
        
        let result = DetectionResult(
            currentPhase: currentPhase,
            confidence: confidence,
            signals: best.signals,
            speakerBalance: prospectRatio,
            balanceAdvice: balanceAdvice,
            phaseProgress: progress,
            suggestTransition: suggestTransition,
            transitionReason: transitionReason
        )
        
        lastDetection = result
        return result
    }
    
    /// Force switch to a phase (manual override)
    func setPhase(_ phase: SalesPhase, at timestamp: TimeInterval) {
        phaseHistory.append((phase: currentPhase, timestamp: timestamp))
        currentPhase = phase
        phaseStartTime = timestamp
    }
    
    func reset() {
        currentPhase = .ouverture
        phaseStartTime = 0
        phaseHistory.removeAll()
        mySegmentCount = 0; otherSegmentCount = 0
        myWordCount = 0; otherWordCount = 0
    }
    
    // MARK: - Private
    
    private func updateSpeakerStats(_ segments: [TranscriptionSegment]) {
        mySegmentCount = segments.filter { $0.speaker == .me }.count
        otherSegmentCount = segments.filter { $0.speaker == .other }.count
        myWordCount = segments.filter { $0.speaker == .me }.reduce(0) { $0 + $1.text.split(separator: " ").count }
        otherWordCount = segments.filter { $0.speaker == .other }.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}
