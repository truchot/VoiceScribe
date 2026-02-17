import Foundation

/// Template-based local LLM provider — no network, no external dependencies.
///
/// Generates structured summaries and contextual suggestions using
/// rule-based analysis of conversation data. Designed as the default
/// fallback when no API key is configured.
///
/// Can be replaced by APILLMProvider for Claude/OpenAI-powered generation.
final class LocalLLMProvider: LLMProvider {

    // MARK: - Generate

    func generate(prompt: String, config: LLMConfig) async throws -> LLMResponse {
        let start = Date()
        let text = "Réponse générée localement pour: \(prompt.prefix(100))..."
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return LLMResponse(text: text, tokensUsed: text.count / 4, latencyMs: latency, backend: .local)
    }

    // MARK: - Summarize

    func summarize(
        transcript: String,
        report: PostCallReport?,
        topics: [DetectedTopic],
        config: LLMConfig
    ) async throws -> SessionSummary {
        let sessionId = UUID()

        let executiveSummary = buildExecutiveSummary(transcript: transcript, report: report)
        let keyPoints = extractKeyPoints(transcript: transcript, topics: topics, report: report)
        let actionItems = extractActionItems(transcript: transcript, topics: topics)
        let sentimentArc = buildSentimentArc(report: report)
        let nextSteps = buildNextSteps(topics: topics, report: report)
        let feedback = buildCoachingFeedback(report: report)

        return SessionSummary(
            sessionId: sessionId,
            backend: .local,
            executiveSummary: executiveSummary,
            keyPoints: keyPoints,
            actionItems: actionItems,
            sentimentArc: sentimentArc,
            nextSteps: nextSteps,
            coachingFeedback: feedback
        )
    }

    // MARK: - Suggest Response

    func suggestResponse(
        recentText: String,
        movement: ConversationMovement,
        emotion: EmotionalState,
        topics: [DetectedTopic],
        config: LLMConfig
    ) async throws -> [ResponseSuggestion] {
        let lower = recentText.lowercased()
        var suggestions: [ResponseSuggestion] = []
        let timestamp = Date().timeIntervalSinceReferenceDate

        // Detect context and generate appropriate suggestions
        let intent = detectIntent(lower)
        let label = emotion.label

        // 1. Objection handling
        if intent == .objecting || matchesAny(lower, Self.objectionMarkers) {
            suggestions.append(contentsOf: objectionSuggestions(text: lower, topics: topics, timestamp: timestamp))
        }

        // 2. Buying signals → closing opportunity
        if intent == .committing || matchesAny(lower, Self.buyingMarkers) || (label == .enthusiastic && emotion.valence > 0.4) {
            suggestions.append(contentsOf: closingSuggestions(movement: movement, timestamp: timestamp))
        }

        // 3. Disengagement → reengagement
        if label == .disengaged || label == .hesitant || (emotion.arousal < -0.3 && emotion.valence < 0) {
            suggestions.append(contentsOf: reengagementSuggestions(movement: movement, topics: topics, timestamp: timestamp))
        }

        // 4. Movement-specific deepening questions
        if suggestions.isEmpty || intent == .neutral {
            suggestions.append(contentsOf: movementSuggestions(movement: movement, topics: topics, timestamp: timestamp))
        }

        return suggestions
    }

    // MARK: - Summary Builders

    private func buildExecutiveSummary(transcript: String, report: PostCallReport?) -> String {
        let lines = transcript.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let wordCount = transcript.split(separator: " ").count

        var summary = ""

        if let report = report {
            let duration = formatDuration(report.totalDuration)
            let movements = report.movementCount
            let fluidity = Int(report.averageFluidityScore * 100)
            let qual = Int(report.memoryReport.qualificationScore * 100)
            summary = "Appel de \(duration) couvrant \(movements) mouvements conversationnels. "
            summary += "Score de fluidité: \(fluidity)%, qualification BANT: \(qual)%. "

            if report.averageFluidityScore > 0.7 {
                summary += "La conversation a été fluide et bien structurée. "
            } else if report.averageFluidityScore > 0.4 {
                summary += "La conversation a été correcte avec quelques axes d'amélioration. "
            } else {
                summary += "La conversation nécessite un travail sur la structure et les transitions. "
            }
        } else if wordCount > 20 {
            summary = "Conversation de \(lines.count) échanges (\(wordCount) mots). "
        } else {
            summary = "Session courte avec peu d'échanges enregistrés. "
        }

        if !report?.contextSummary.isEmpty ?? false {
            summary += report!.contextSummary
        }

        return summary
    }

    private func extractKeyPoints(transcript: String, topics: [DetectedTopic], report: PostCallReport?) -> [String] {
        var points: [String] = []

        // From topics
        for topic in topics.prefix(5) {
            switch topic.category {
            case .pricing: points.append("Discussion budget/prix : \(topic.name)")
            case .timeline: points.append("Timeline identifiée : \(topic.name)")
            case .competitor: points.append("Concurrent mentionné : \(topic.name)")
            case .pain: points.append("Problème identifié : \(topic.name)")
            case .decision: points.append("Processus de décision abordé : \(topic.name)")
            case .technical: points.append("Point technique discuté : \(topic.name)")
            case .success: points.append("Critère de succès : \(topic.name)")
            case .general: break
            }
        }

        // From report memory
        if let report = report {
            let collected = report.memoryReport.slotsCollected
            if collected.count > 0 {
                points.append("\(collected.count) informations clés captées (BANT)")
            }
            if !report.memoryReport.missingCritical.isEmpty {
                points.append("\(report.memoryReport.missingCritical.count) informations critiques manquantes")
            }
        }

        // Ensure at least one point
        if points.isEmpty {
            points.append("Session enregistrée — consulter la transcription pour les détails")
        }

        return points
    }

    private func extractActionItems(transcript: String, topics: [DetectedTopic]) -> [ActionItem] {
        var items: [ActionItem] = []

        let lower = transcript.lowercased()

        // Detect follow-up commitments
        if lower.contains("démo") || lower.contains("demo") || lower.contains("présentation") {
            items.append(ActionItem(title: "Planifier une démo/présentation", priority: .high))
        }
        if lower.contains("devis") || lower.contains("proposition") || lower.contains("offre") {
            items.append(ActionItem(title: "Envoyer devis/proposition commerciale", priority: .high))
        }
        if lower.contains("rappeler") || lower.contains("recontacter") || lower.contains("revenir") {
            items.append(ActionItem(title: "Planifier un rappel/suivi", priority: .medium))
        }
        if lower.contains("document") || lower.contains("information") || lower.contains("envoyer") {
            items.append(ActionItem(title: "Envoyer documentation complémentaire", priority: .medium))
        }

        // From missing critical info
        for topic in topics where topic.category == .decision {
            items.append(ActionItem(title: "Identifier le circuit de décision", priority: .high))
        }

        if items.isEmpty {
            items.append(ActionItem(title: "Envoyer un email de suivi", priority: .low))
        }

        return items
    }

    private func buildSentimentArc(report: PostCallReport?) -> String {
        guard let report = report, !report.movementTimeline.isEmpty else {
            return "Données insuffisantes pour établir un arc émotionnel."
        }

        let fluidity = report.averageFluidityScore
        if fluidity > 0.7 {
            return "Arc positif : la conversation a été fluide avec un bon engagement du prospect tout au long de l'échange."
        } else if fluidity > 0.4 {
            return "Arc mixte : quelques moments de tension ou d'hésitation mais l'engagement global est resté correct."
        } else {
            return "Arc difficile : des signes de désengagement ou de résistance significatifs pendant l'échange."
        }
    }

    private func buildNextSteps(topics: [DetectedTopic], report: PostCallReport?) -> String {
        var steps: [String] = []

        if let report = report {
            if report.memoryReport.qualificationScore < 0.5 {
                steps.append("Compléter la qualification BANT lors du prochain contact")
            }
            if !report.memoryReport.missingCritical.isEmpty {
                let missing = report.memoryReport.missingCritical.map(\.label).joined(separator: ", ")
                steps.append("Obtenir les informations manquantes: \(missing)")
            }
        }

        let hasPricing = topics.contains { $0.category == .pricing }
        let hasDecision = topics.contains { $0.category == .decision }

        if hasPricing && !hasDecision {
            steps.append("Identifier le processus de décision et le décisionnaire")
        }

        if steps.isEmpty {
            steps.append("Envoyer un résumé de l'appel et proposer une prochaine étape")
        }

        return steps.joined(separator: "\n- ")
    }

    private func buildCoachingFeedback(report: PostCallReport?) -> String {
        guard let report = report else {
            return "Pas de données de coaching disponibles pour cette session."
        }

        var feedback: [String] = []

        if report.averageFluidityScore > 0.7 {
            feedback.append("Bonne fluidité conversationnelle (\(Int(report.averageFluidityScore * 100))%)")
        } else {
            feedback.append("Travailler les transitions entre mouvements (fluidité: \(Int(report.averageFluidityScore * 100))%)")
        }

        if report.memoryReport.qualificationScore > 0.6 {
            feedback.append("Bonne qualification BANT (\(Int(report.memoryReport.qualificationScore * 100))%)")
        } else {
            feedback.append("Renforcer la qualification : poser plus de questions BANT")
        }

        let movementCount = report.movementTimeline.count
        if movementCount < 4 {
            feedback.append("Explorer davantage de mouvements — \(movementCount)/11 couverts")
        }

        return feedback.joined(separator: ". ") + "."
    }

    // MARK: - Suggestion Generators

    private func objectionSuggestions(text: String, topics: [DetectedTopic], timestamp: TimeInterval) -> [ResponseSuggestion] {
        var suggestions: [ResponseSuggestion] = []

        if text.contains("cher") || text.contains("prix") || text.contains("budget") {
            suggestions.append(ResponseSuggestion(
                text: "Je comprends votre préoccupation sur le prix. Quel ROI attendez-vous sur ce type d'investissement ?",
                context: .objectionHandling, confidence: 0.9, timestamp: timestamp
            ))
            suggestions.append(ResponseSuggestion(
                text: "Si je vous montre comment on peut réduire vos coûts actuels de 30%, est-ce que ça change la donne ?",
                context: .valueProposition, confidence: 0.85, timestamp: timestamp
            ))
        } else if text.contains("concurrent") || text.contains("alternative") || text.contains("comparé") {
            suggestions.append(ResponseSuggestion(
                text: "Qu'est-ce qui vous plaît le plus chez votre solution actuelle ?",
                context: .objectionHandling, confidence: 0.85, timestamp: timestamp
            ))
        } else if text.contains("pas le moment") || text.contains("plus tard") || text.contains("pas priorit") {
            suggestions.append(ResponseSuggestion(
                text: "Je comprends. Qu'est-ce qui devrait changer pour que ce devienne une priorité ?",
                context: .objectionHandling, confidence: 0.9, timestamp: timestamp
            ))
        } else {
            suggestions.append(ResponseSuggestion(
                text: "Je comprends votre point de vue. Pouvez-vous m'en dire plus sur ce qui vous freine ?",
                context: .objectionHandling, confidence: 0.8, timestamp: timestamp
            ))
        }

        return suggestions
    }

    private func closingSuggestions(movement: ConversationMovement, timestamp: TimeInterval) -> [ResponseSuggestion] {
        [
            ResponseSuggestion(
                text: "Excellent ! On peut avancer ensemble. Quelle serait la prochaine étape idéale pour vous ?",
                context: .closingOpportunity, confidence: 0.9, timestamp: timestamp
            ),
            ResponseSuggestion(
                text: "Je sens qu'on est alignés. Voulez-vous qu'on regarde le calendrier pour planifier la suite ?",
                context: .closingOpportunity, confidence: 0.85, timestamp: timestamp
            )
        ]
    }

    private func reengagementSuggestions(movement: ConversationMovement, topics: [DetectedTopic], timestamp: TimeInterval) -> [ResponseSuggestion] {
        var suggestions: [ResponseSuggestion] = []

        suggestions.append(ResponseSuggestion(
            text: "J'aimerais bien comprendre : quel est votre plus grand défi au quotidien sur ce sujet ?",
            context: .reengagement, confidence: 0.85, timestamp: timestamp
        ))

        if topics.contains(where: { $0.category == .pain }) {
            suggestions.append(ResponseSuggestion(
                text: "Vous avez mentionné un problème intéressant tout à l'heure. Quel impact ça a sur votre équipe concrètement ?",
                context: .reengagement, confidence: 0.9, timestamp: timestamp
            ))
        } else {
            suggestions.append(ResponseSuggestion(
                text: "Si vous aviez une baguette magique, qu'est-ce que vous changeriez dans votre processus actuel ?",
                context: .reengagement, confidence: 0.8, timestamp: timestamp
            ))
        }

        return suggestions
    }

    private func movementSuggestions(movement: ConversationMovement, topics: [DetectedTopic], timestamp: TimeInterval) -> [ResponseSuggestion] {
        switch movement {
        case .accueil, .cadrage:
            return [ResponseSuggestion(
                text: "Avant de commencer, qu'est-ce qui vous a amené à accepter cet échange aujourd'hui ?",
                context: .questionToAsk, confidence: 0.85, timestamp: timestamp
            )]
        case .enjeux, .profondeur:
            return [
                ResponseSuggestion(
                    text: "Pouvez-vous me décrire une journée type où ce problème se manifeste ?",
                    context: .questionToAsk, confidence: 0.9, timestamp: timestamp
                ),
                ResponseSuggestion(
                    text: "Quel impact financier estimez-vous pour ce problème sur une année ?",
                    context: .questionToAsk, confidence: 0.85, timestamp: timestamp
                )
            ]
        case .qualification:
            return [
                ResponseSuggestion(
                    text: "Qui d'autre dans votre organisation serait impliqué dans cette décision ?",
                    context: .questionToAsk, confidence: 0.9, timestamp: timestamp
                ),
                ResponseSuggestion(
                    text: "Avez-vous un budget alloué pour ce type de solution ?",
                    context: .questionToAsk, confidence: 0.85, timestamp: timestamp
                )
            ]
        case .proposition, .dialogue:
            return [ResponseSuggestion(
                text: "Comment est-ce que cette fonctionnalité s'intégrerait dans votre workflow actuel ?",
                context: .questionToAsk, confidence: 0.85, timestamp: timestamp
            )]
        case .engagement:
            return [ResponseSuggestion(
                text: "On peut récapituler ensemble les points clés et définir les prochaines étapes ?",
                context: .closingOpportunity, confidence: 0.9, timestamp: timestamp
            )]
        default:
            return [ResponseSuggestion(
                text: "Qu'est-ce qui serait le plus utile pour vous à ce stade de notre échange ?",
                context: .general, confidence: 0.75, timestamp: timestamp
            )]
        }
    }

    // MARK: - Utility

    private func detectIntent(_ text: String) -> ConversationalIntent {
        if text.contains("?") { return .asking }
        if matchesAny(text, Self.objectionMarkers) { return .objecting }
        if matchesAny(text, Self.buyingMarkers) { return .committing }
        return .neutral
    }

    private func matchesAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let m = Int(d) / 60, s = Int(d) % 60
        return "\(m)m\(String(format: "%02d", s))s"
    }

    // MARK: - Pattern Constants

    private static let objectionMarkers = [
        "trop cher", "pas le budget", "pas intéress", "pas le moment",
        "pas priorit", "concurrent", "alternative", "hésit", "pas besoin",
        "c'est cher", "trop coûteux", "pas convaincant"
    ]

    private static let buyingMarkers = [
        "on signe", "allons-y", "prochaine étape", "quand on commence",
        "parfait", "exactement", "c'est ce qu'il nous faut", "on avance",
        "planifier", "démo", "je suis prêt", "je valide"
    ]
}
