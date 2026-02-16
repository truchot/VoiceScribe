import Foundation

/// Real-time coaching suggestions based on prospect's emotional state.
///
/// This is the bridge between sentiment analysis and actionable sales coaching.
/// Instead of just showing "😤 Frustré", it tells the salesperson WHAT TO SAY
/// to acknowledge the emotion and guide the conversation.
///
/// Design principles:
/// - Empathy first: always validate the emotion before redirecting
/// - Short phrases: must be glanceable in <2 seconds during a live call
/// - Contextual: adapts to emotion + trend + conversation phase
/// - Non-manipulative: genuine empathy, not tricks
final class CoachingSuggestionEngine {
    
    // MARK: - Configuration
    
    struct Config {
        /// Minimum confidence to show a suggestion
        var minConfidence: Float = CoachingThresholds.suggestionMinConfidence
        
        /// Minimum time between suggestion changes (avoid flickering)
        var cooldownSeconds: TimeInterval = CoachingThresholds.suggestionCooldown
        
        /// Include transition phrases when emotion shifts
        var showTransitionPhrases: Bool = true
    }
    
    // MARK: - Output
    
    struct CoachingSuggestion {
        /// The primary empathetic phrase to say
        let phrase: String
        
        /// Why this phrase (brief coaching rationale)
        let rationale: String
        
        /// The emotion being addressed
        let targetEmotion: EmotionLabel
        
        /// Urgency: how important it is to act now
        let urgency: SuggestionUrgency
        
        /// Category of the suggestion
        let category: SuggestionCategory
        
        /// Alternative phrases (pick the one that feels natural)
        let alternatives: [String]
    }
    
    enum SuggestionUrgency: String {
        case low = "Info"           // Just awareness
        case medium = "Attention"   // Should adjust tone
        case high = "Agir"          // Should intervene now
        case critical = "Urgent"    // Risk of losing prospect
    }
    
    enum SuggestionCategory: String {
        case empathize = "Empathie"         // Acknowledge their feeling
        case reassure = "Rassurer"          // Reduce anxiety
        case reengage = "Réengager"         // Bring them back
        case validate = "Valider"           // Confirm their concern is legitimate
        case redirect = "Recadrer"          // Steer conversation
        case celebrate = "Célébrer"         // Reinforce positive momentum
        case deepen = "Approfondir"         // Dig into what they're feeling
    }
    
    // MARK: - State
    
    private let config: Config
    private var lastSuggestionTime: TimeInterval = 0
    private var lastEmotion: EmotionLabel = .neutral
    private var emotionStreak: Int = 0  // How many updates same emotion
    private var recentEmotions: [EmotionLabel] = []
    
    // MARK: - Init
    
    init(config: Config = Config()) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Generate a coaching suggestion based on current emotional state.
    /// Call this every time sentiment updates (~500ms).
    func suggest(
        emotion: EmotionalState,
        previousEmotion: EmotionLabel?,
        timestamp: TimeInterval
    ) -> CoachingSuggestion? {
        
        guard emotion.confidence >= config.minConfidence else { return nil }
        
        let label = emotion.label
        
        // Track streak
        if label == lastEmotion {
            emotionStreak += 1
        } else {
            emotionStreak = 0
        }
        
        recentEmotions.append(label)
        if recentEmotions.count > 20 { recentEmotions.removeFirst() }
        
        // Cooldown check
        let timeSinceLast = timestamp - lastSuggestionTime
        let needsUpdate = label != lastEmotion || timeSinceLast > config.cooldownSeconds * 3
        
        guard needsUpdate || emotionStreak == 3 else { return nil }
        
        lastSuggestionTime = timestamp
        lastEmotion = label
        
        // Check if this is a transition
        let isShift = previousEmotion != nil && previousEmotion != label
        let isEscalation = isNegativeEscalation(from: previousEmotion, to: label)
        
        return buildSuggestion(
            emotion: emotion,
            label: label,
            isShift: isShift,
            isEscalation: isEscalation,
            streak: emotionStreak
        )
    }
    
    /// Reset state (new session)
    func reset() {
        lastEmotion = .neutral
        emotionStreak = 0
        recentEmotions.removeAll()
        lastSuggestionTime = 0
    }
    
    // MARK: - Suggestion Builder
    
    private func buildSuggestion(
        emotion: EmotionalState,
        label: EmotionLabel,
        isShift: Bool,
        isEscalation: Bool,
        streak: Int
    ) -> CoachingSuggestion {
        
        switch label {
            
        // ========================================
        // NEGATIVE EMOTIONS (need intervention)
        // ========================================
            
        case .frustrated:
            let urgency: SuggestionUrgency = streak > 4 ? .critical : isEscalation ? .high : .medium
            
            if streak > 4 {
                return CoachingSuggestion(
                    phrase: "Je sens que ce point vous préoccupe vraiment. Prenons le temps d'en parler.",
                    rationale: "Frustration persistante — il faut nommer l'éléphant dans la pièce avant de continuer.",
                    targetEmotion: label,
                    urgency: urgency,
                    category: .validate,
                    alternatives: [
                        "C'est un sujet important et votre réaction est tout à fait légitime.",
                        "Je comprends votre frustration. Qu'est-ce qui vous bloque le plus ?",
                        "Vous avez raison de soulever ce point. Regardons ça ensemble."
                    ]
                )
            }
            
            return CoachingSuggestion(
                phrase: "Je comprends, c'est une préoccupation légitime.",
                rationale: "Validez la frustration sans vous justifier. L'empathie avant les arguments.",
                targetEmotion: label,
                urgency: urgency,
                category: .empathize,
                alternatives: [
                    "C'est tout à fait normal de réagir comme ça.",
                    "Je vois ce que vous voulez dire, et c'est un point important.",
                    "Votre point de vue est compréhensible."
                ]
            )
            
        case .hesitant:
            let urgency: SuggestionUrgency = streak > 5 ? .high : .medium
            
            if emotion.dominance < -0.5 {
                return CoachingSuggestion(
                    phrase: "Il n'y a pas de mauvaise question. Qu'est-ce qui vous ferait hésiter ?",
                    rationale: "Dominance très basse — la personne n'ose pas exprimer son doute. Ouvrez l'espace.",
                    targetEmotion: label,
                    urgency: urgency,
                    category: .reassure,
                    alternatives: [
                        "Prenez votre temps, c'est une décision importante.",
                        "Beaucoup de nos clients se posent les mêmes questions à cette étape.",
                        "C'est tout à fait normal d'hésiter. Qu'est-ce qui vous aiderait à y voir plus clair ?"
                    ]
                )
            }
            
            return CoachingSuggestion(
                phrase: "Qu'est-ce qui vous ferait dire oui en toute confiance ?",
                rationale: "Hésitation détectée — guidez vers l'expression du besoin non dit.",
                targetEmotion: label,
                urgency: urgency,
                category: .deepen,
                alternatives: [
                    "Si je peux clarifier un point, n'hésitez pas.",
                    "Qu'est-ce qui serait le plus rassurant pour vous à ce stade ?",
                    "Y a-t-il un élément qui vous manque pour avancer sereinement ?"
                ]
            )
            
        case .disengaged:
            return CoachingSuggestion(
                phrase: "Pour être sûr de ne pas vous faire perdre votre temps, qu'est-ce qui compte le plus pour vous ?",
                rationale: "Décrochage détecté — reprenez le contrôle en recentrant sur leurs priorités.",
                targetEmotion: label,
                urgency: streak > 3 ? .high : .medium,
                category: .reengage,
                alternatives: [
                    "Je vais être direct : quel serait le point le plus utile à aborder maintenant ?",
                    "Est-ce que ce sujet correspond bien à votre besoin ou on ajuste ?",
                    "Qu'est-ce qui vous serait le plus utile dans les prochaines minutes ?"
                ]
            )
            
        // ========================================
        // POSITIVE EMOTIONS (reinforce & advance)
        // ========================================
            
        case .enthusiastic:
            return CoachingSuggestion(
                phrase: "Super ! Vous voyez exactement le potentiel. 🎯",
                rationale: "Enthousiasme = signal d'achat. C'est le moment de concrétiser.",
                targetEmotion: label,
                urgency: .medium,
                category: .celebrate,
                alternatives: [
                    "C'est exactement ce que nos meilleurs clients nous disent.",
                    "Votre vision est la bonne. On passe aux étapes concrètes ?",
                    "Ravi que ça résonne. Comment on avance ensemble ?"
                ]
            )
            
        case .satisfied:
            return CoachingSuggestion(
                phrase: "C'est un bon signe. Qu'est-ce qui vous plaît le plus dans ce qu'on a vu ?",
                rationale: "Satisfaction = ancrer le positif. Faites-leur verbaliser ce qu'ils aiment.",
                targetEmotion: label,
                urgency: .low,
                category: .deepen,
                alternatives: [
                    "Content que ça corresponde. Quel aspect vous parle le plus ?",
                    "Qu'est-ce qui fait la différence pour vous ?",
                    "Si vous deviez retenir une chose, ce serait quoi ?"
                ]
            )
            
        case .confident:
            return CoachingSuggestion(
                phrase: "Parfait, on est alignés. Quelle serait la prochaine étape idéale pour vous ?",
                rationale: "Confiance élevée — ne pas sur-vendre, avancer vers l'action.",
                targetEmotion: label,
                urgency: .low,
                category: .redirect,
                alternatives: [
                    "On est sur la même longueur d'onde. On formalise ?",
                    "Votre clarté sur le sujet est appréciable. Comment on concrétise ?",
                    "Vous avez une vision claire. On peut passer à la mise en œuvre."
                ]
            )
            
        case .animated:
            return CoachingSuggestion(
                phrase: "Je vois que le sujet vous parle ! Dites-m'en plus.",
                rationale: "Énergie haute — laissez parler, c'est là que les vrais besoins sortent.",
                targetEmotion: label,
                urgency: .low,
                category: .deepen,
                alternatives: [
                    "Continuez, c'est passionnant.",
                    "C'est exactement ce type de retour qui nous aide à avancer.",
                    "J'aime cette énergie. Qu'est-ce qui vous motive le plus ?"
                ]
            )
            
        // ========================================
        // NEUTRAL
        // ========================================
            
        case .neutral:
            if streak > 10 {
                // Neutral for too long = potentially disengaged but not showing it
                return CoachingSuggestion(
                    phrase: "Et vous, qu'en pensez-vous ? J'aimerais avoir votre ressenti.",
                    rationale: "Neutre prolongé — sollicitez une réaction pour relancer l'engagement.",
                    targetEmotion: label,
                    urgency: .low,
                    category: .reengage,
                    alternatives: [
                        "J'ai beaucoup parlé, je suis curieux de votre avis.",
                        "Qu'est-ce qui vous vient à l'esprit en entendant ça ?",
                        "Ça fait écho à quelque chose chez vous ?"
                    ]
                )
            }
            
            return CoachingSuggestion(
                phrase: "La conversation se passe bien. Continuez sur ce rythme.",
                rationale: "État neutre — pas d'action nécessaire.",
                targetEmotion: label,
                urgency: .low,
                category: .validate,
                alternatives: []
            )
        }
    }
    
    // MARK: - Helpers
    
    private func isNegativeEscalation(from prev: EmotionLabel?, to current: EmotionLabel) -> Bool {
        guard let prev = prev else { return false }
        
        let negativeLevel: [EmotionLabel: Int] = [
            .enthusiastic: 0, .satisfied: 0, .confident: 0, .animated: 0,
            .neutral: 1,
            .hesitant: 2,
            .frustrated: 3,
            .disengaged: 3
        ]
        
        let prevLevel = negativeLevel[prev] ?? 1
        let currentLevel = negativeLevel[current] ?? 1
        
        return currentLevel > prevLevel
    }
}
