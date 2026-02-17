import Foundation

/// Context-aware semantic text analysis for conversational sentiment.
///
/// Goes beyond keyword matching (TextSignalAnalyzer) by understanding:
/// - Sentence-level intent (question, objection, agreement, commitment, deflection)
/// - Topic tracking across the conversation (pricing, timeline, decision, etc.)
/// - Certainty/engagement levels from linguistic cues
/// - Contextual polarity (negation-aware, discourse markers)
///
/// Designed for French commercial conversations with English fallback.
/// All processing is local, no ML model required (<5ms per analysis).
final class SemanticSentimentAnalyzer: SemanticSentimentProvider {

    // MARK: - State

    private var detectedTopics: [DetectedTopic] = []
    private var conversationContext: [ContextEntry] = []
    private let maxContextEntries = 50

    // MARK: - Analysis

    func analyze(text: String, speaker: Speaker, timestamp: TimeInterval) -> SemanticAnalysis {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return .empty(at: timestamp) }

        let intent = detectIntent(lower)
        let topics = detectTopics(lower, timestamp: timestamp)
        let sentiment = analyzeSentiment(lower, intent: intent)
        let confidence = computeConfidence(text)

        // Track context
        conversationContext.append(ContextEntry(
            text: lower, speaker: speaker, intent: intent,
            sentiment: sentiment, timestamp: timestamp
        ))
        if conversationContext.count > maxContextEntries {
            conversationContext.removeFirst()
        }

        return SemanticAnalysis(
            sentiment: sentiment,
            topics: topics,
            intent: intent,
            confidence: confidence,
            timestamp: timestamp
        )
    }

    func recentTopics() -> [DetectedTopic] {
        detectedTopics
    }

    func conversationIntent(from text: String) -> ConversationalIntent {
        detectIntent(text.lowercased())
    }

    func reset() {
        detectedTopics.removeAll()
        conversationContext.removeAll()
    }

    // MARK: - Intent Detection

    private func detectIntent(_ text: String) -> ConversationalIntent {
        // Priority-ordered intent detection

        // 1. Question detection (? or interrogative patterns)
        if text.contains("?") || matchesAny(text, patterns: Self.questionPatterns) {
            return .asking
        }

        // 2. Commitment/closing signals
        if matchesAny(text, patterns: Self.commitmentPatterns) {
            return .committing
        }

        // 3. Objection detection (price, refusal, concerns)
        if matchesAny(text, patterns: Self.objectionPatterns) && !isNegated(text, patterns: Self.objectionPatterns) {
            return .objecting
        }

        // 4. Deflection (authority, delay)
        if matchesAny(text, patterns: Self.deflectionPatterns) {
            return .deflecting
        }

        // 5. Agreement
        if matchesAny(text, patterns: Self.agreementPatterns) {
            return .agreeing
        }

        // 6. Clarification request
        if matchesAny(text, patterns: Self.clarificationPatterns) {
            return .clarifying
        }

        // 7. Request
        if matchesAny(text, patterns: Self.requestPatterns) {
            return .requesting
        }

        return .neutral
    }

    // MARK: - Topic Detection

    private func detectTopics(_ text: String, timestamp: TimeInterval) -> [DetectedTopic] {
        var newTopics: [DetectedTopic] = []

        for (category, keywords) in Self.topicKeywords {
            if matchesAny(text, patterns: keywords) {
                // Check if topic already exists
                if let idx = detectedTopics.firstIndex(where: { $0.category == category }) {
                    detectedTopics[idx].incrementMention()
                } else {
                    let name = extractTopicName(text, category: category)
                    let topic = DetectedTopic(
                        name: name, category: category,
                        confidence: 0.8, timestamp: timestamp
                    )
                    detectedTopics.append(topic)
                    newTopics.append(topic)
                }
            }
        }

        return newTopics
    }

    // MARK: - Sentiment Analysis

    private func analyzeSentiment(_ text: String, intent: ConversationalIntent) -> SemanticSentiment {
        var polarity: Float = 0.0
        var certainty: Float = 0.5
        var engagement: Float = 0.5
        var formality: Float = 0.5

        // Polarity from positive/negative markers
        let positiveCount = countMatches(text, patterns: Self.positiveMarkers)
        let negativeCount = countMatches(text, patterns: Self.negativeMarkers)
        let negationCount = countMatches(text, patterns: Self.negationMarkers)

        polarity = Float(positiveCount - negativeCount) * 0.25
        // Negation can flip polarity
        if negationCount > 0 && positiveCount > negativeCount {
            polarity *= -0.5
        }

        // Intent influences polarity
        switch intent {
        case .agreeing, .committing: polarity += 0.3
        case .objecting: polarity -= 0.3
        case .deflecting: polarity -= 0.15
        default: break
        }

        polarity = max(-1.0, min(1.0, polarity))

        // Certainty detection
        let certainWords = countMatches(text, patterns: Self.certaintyMarkers)
        let uncertainWords = countMatches(text, patterns: Self.uncertaintyMarkers)
        certainty = 0.5 + Float(certainWords) * 0.15 - Float(uncertainWords) * 0.15
        certainty = max(0, min(1, certainty))

        // Engagement = text length proxy + engaged markers
        let wordCount = text.split(separator: " ").count
        engagement = min(1.0, Float(wordCount) / 20.0 * 0.5 + 0.3)
        if matchesAny(text, patterns: Self.engagementMarkers) {
            engagement = min(1.0, engagement + 0.2)
        }
        if wordCount <= 3 { engagement = min(engagement, 0.3) }

        // Formality
        if matchesAny(text, patterns: Self.formalMarkers) {
            formality = min(1.0, formality + 0.2)
        }
        if matchesAny(text, patterns: Self.informalMarkers) {
            formality = max(0, formality - 0.2)
        }

        return SemanticSentiment(
            polarity: polarity,
            certainty: certainty,
            formality: formality,
            engagement: engagement
        )
    }

    // MARK: - Confidence

    private func computeConfidence(_ text: String) -> Float {
        let wordCount = text.split(separator: " ").count
        // More words = higher confidence in analysis
        let lengthFactor = min(1.0, Float(wordCount) / 10.0)
        return max(0.3, lengthFactor)
    }

    // MARK: - Utility

    private func matchesAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains(where: { text.contains($0) })
    }

    private func countMatches(_ text: String, patterns: [String]) -> Int {
        patterns.reduce(0) { count, pattern in
            count + (text.contains(pattern) ? 1 : 0)
        }
    }

    private func isNegated(_ text: String, patterns: [String]) -> Bool {
        // Check if the pattern match is preceded by a negation
        for pattern in patterns where text.contains(pattern) {
            if let range = text.range(of: pattern) {
                let prefix = String(text[text.startIndex..<range.lowerBound])
                let lastWords = prefix.split(separator: " ").suffix(3).joined(separator: " ")
                if Self.negationMarkers.contains(where: { lastWords.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private func extractTopicName(_ text: String, category: TopicCategory) -> String {
        // Return a short descriptive name based on the category
        switch category {
        case .pricing: return "prix/budget"
        case .timeline: return "timing/deadline"
        case .competitor: return "concurrent"
        case .technical: return "technique"
        case .decision: return "décision"
        case .pain: return "problème/douleur"
        case .success: return "résultat/succès"
        case .general: return "général"
        }
    }

    // MARK: - Context Tracking

    private struct ContextEntry {
        let text: String
        let speaker: Speaker
        let intent: ConversationalIntent
        let sentiment: SemanticSentiment
        let timestamp: TimeInterval
    }

    // MARK: - Pattern Dictionaries

    // Intent patterns (French-first, with English fallback)

    private static let questionPatterns = [
        "comment", "pourquoi", "quand", "combien", "est-ce que",
        "qu'est-ce", "quel", "quelle", "quels", "quelles",
        "how", "why", "when", "what", "which"
    ]

    private static let objectionPatterns = [
        "trop cher", "trop coûteux", "hors budget", "pas le budget",
        "pas intéress", "pas convaincant", "pas besoin", "pas priorit",
        "pas le moment", "pas maintenant", "on n'a pas", "je ne pense pas",
        "je ne crois pas", "ça ne", "c'est cher", "le prix est élevé",
        "too expensive", "not interested", "no budget", "not a priority"
    ]

    private static let agreementPatterns = [
        "tout à fait", "absolument", "exactement", "c'est vrai",
        "je suis d'accord", "bien sûr", "parfait", "super",
        "excellent", "ça me convient", "ça marche", "ok pour",
        "je confirme", "on est aligné", "exactly", "absolutely", "agreed"
    ]

    private static let commitmentPatterns = [
        "on signe", "on y va", "je suis prêt", "allons-y",
        "prochaine étape", "next step", "quand on commence",
        "envoyez le contrat", "envoyez-moi", "je valide",
        "c'est bon pour moi", "on avance", "go for it", "let's do it"
    ]

    private static let deflectionPatterns = [
        "faut que j'en parle", "je dois en parler", "mon directeur",
        "mon manager", "mon responsable", "le comité", "la direction",
        "on verra plus tard", "revenez plus tard", "pas le décideur",
        "need to check with", "my manager", "not the decision maker"
    ]

    private static let clarificationPatterns = [
        "c'est-à-dire", "vous voulez dire", "je comprends que",
        "si j'ai bien compris", "en d'autres termes", "autrement dit",
        "you mean", "in other words", "to clarify"
    ]

    private static let requestPatterns = [
        "pouvez-vous", "pourriez-vous", "j'aimerais", "je voudrais",
        "est-il possible", "serait-il possible", "montrez-moi",
        "could you", "can you", "I would like", "show me"
    ]

    // Sentiment markers

    private static let positiveMarkers = [
        "excellent", "parfait", "super", "génial", "formidable",
        "intéressant", "impressionnant", "bien", "bon", "bonne",
        "efficace", "utile", "pratique", "clair", "simple",
        "great", "good", "nice", "impressive", "useful"
    ]

    private static let negativeMarkers = [
        "problème", "souci", "difficulté", "compliqué", "complexe",
        "cher", "coûteux", "lent", "lourd", "pénible", "frustrant",
        "impossible", "risqué", "danger", "inquiétant",
        "problem", "issue", "difficult", "expensive", "slow"
    ]

    private static let negationMarkers = [
        "ne ", "n'", "pas ", "plus ", "jamais ", "rien ",
        "aucun", "non", "sans ",
        "not ", "no ", "never ", "without "
    ]

    // Certainty markers

    private static let certaintyMarkers = [
        "sûr", "certain", "évident", "clairement", "sans doute",
        "absolument", "définitivement", "je sais", "c'est clair",
        "sure", "certain", "clearly", "definitely"
    ]

    private static let uncertaintyMarkers = [
        "peut-être", "je ne sais pas", "je pense", "il me semble",
        "on verra", "pas sûr", "hésit", "possiblement", "éventuellement",
        "maybe", "perhaps", "not sure", "I think", "possibly"
    ]

    // Engagement markers

    private static let engagementMarkers = [
        "dites-m'en plus", "expliquez", "intéress", "j'aimerais savoir",
        "racontez", "montrez", "comment ça fonctionne", "concrètement",
        "tell me more", "explain", "interested", "how does it work"
    ]

    // Formality markers

    private static let formalMarkers = [
        "permettez", "veuillez", "cordialement", "monsieur", "madame",
        "je vous prie", "serait-il envisageable", "dans le cadre de"
    ]

    private static let informalMarkers = [
        "genre", "en gros", "quoi", "bref", "du coup", "en fait",
        "carrément", "vachement", "trop bien"
    ]

    // Topic keywords

    private static let topicKeywords: [TopicCategory: [String]] = [
        .pricing: ["budget", "prix", "coût", "tarif", "devis", "investissement",
                    "facturation", "abonnement", "price", "cost", "budget", "quote"],
        .timeline: ["deadline", "délai", "calendrier", "planning", "trimestre",
                     "date", "quand", "urgence", "timeline", "quarter", "when", "déployer"],
        .competitor: ["concurrent", "alternative", "comparé à", "versus",
                      "salesforce", "hubspot", "microsoft", "google",
                      "competitor", "alternative", "compared to"],
        .technical: ["intégration", "api", "technique", "infrastructure",
                     "sécurité", "données", "migration", "technical",
                     "integration", "security", "data"],
        .decision: ["décideur", "directeur", "comité", "validation",
                    "approbation", "hiérarchie", "decision", "director",
                    "approval", "committee", "qui décide"],
        .pain: ["problème", "difficulté", "challenge", "frustration",
                "perte de temps", "inefficace", "manuel",
                "problem", "issue", "challenge", "pain point", "douleur"],
        .success: ["résultat", "objectif", "amélioration", "gain",
                   "roi", "performance", "succès", "croissance",
                   "result", "goal", "improvement", "roi"]
    ]
}
