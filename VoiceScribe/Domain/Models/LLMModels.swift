import Foundation

// MARK: - LLM Configuration (Value Object)

/// Supported LLM backends for text generation.
enum LLMBackend: String, Codable, CaseIterable {
    case local = "local"
    case claudeAPI = "claude-api"
    case openAIAPI = "openai-api"

    var displayName: String {
        switch self {
        case .local: return "Local (template)"
        case .claudeAPI: return "Claude API"
        case .openAIAPI: return "OpenAI API"
        }
    }

    var requiresAPIKey: Bool { self != .local }
    var isLocal: Bool { self == .local }
}

/// Configuration for LLM-based text generation.
struct LLMConfig: Codable, Equatable {
    var backend: LLMBackend = .local
    var apiKey: String = ""
    var model: String = "claude-sonnet-4-5-20250929"
    var maxTokens: Int = 1024
    var temperature: Float = 0.3
    var systemPrompt: String = ""

    static let `default` = LLMConfig()
}

// MARK: - LLM Response (Value Object)

/// Response from an LLM generation request.
struct LLMResponse {
    let text: String
    let tokensUsed: Int
    let latencyMs: Int
    let backend: LLMBackend
    let timestamp: Date

    init(text: String, tokensUsed: Int = 0, latencyMs: Int = 0, backend: LLMBackend, timestamp: Date = Date()) {
        self.text = text
        self.tokensUsed = tokensUsed
        self.latencyMs = latencyMs
        self.backend = backend
        self.timestamp = timestamp
    }
}

// MARK: - Session Summary (Value Object)

/// AI-generated summary of a completed session.
struct SessionSummary: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let generatedAt: Date
    let backend: LLMBackend

    /// One-paragraph executive summary.
    let executiveSummary: String
    /// Key points from the conversation.
    let keyPoints: [String]
    /// Action items detected.
    let actionItems: [ActionItem]
    /// Prospect sentiment arc (beginning → end).
    let sentimentArc: String
    /// Next steps recommendation.
    let nextSteps: String
    /// Coaching feedback for the seller.
    let coachingFeedback: String

    init(
        sessionId: UUID,
        backend: LLMBackend,
        executiveSummary: String,
        keyPoints: [String],
        actionItems: [ActionItem],
        sentimentArc: String,
        nextSteps: String,
        coachingFeedback: String
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.generatedAt = Date()
        self.backend = backend
        self.executiveSummary = executiveSummary
        self.keyPoints = keyPoints
        self.actionItems = actionItems
        self.sentimentArc = sentimentArc
        self.nextSteps = nextSteps
        self.coachingFeedback = coachingFeedback
    }

    func toMarkdown() -> String {
        var md = "# Synthèse IA\n\n"
        md += "## Résumé\n\n\(executiveSummary)\n\n"

        md += "## Points clés\n\n"
        for point in keyPoints { md += "- \(point)\n" }

        if !actionItems.isEmpty {
            md += "\n## Actions à suivre\n\n"
            for item in actionItems {
                md += "- [\(item.isCompleted ? "x" : " ")] **\(item.title)** — \(item.owner)\n"
                if !item.detail.isEmpty { md += "  \(item.detail)\n" }
            }
        }

        md += "\n## Arc émotionnel\n\n\(sentimentArc)\n\n"
        md += "## Prochaines étapes\n\n\(nextSteps)\n\n"
        md += "## Feedback coaching\n\n\(coachingFeedback)\n"
        md += "\n---\n*Synthèse générée par \(backend.displayName)*\n"
        return md
    }
}

/// An action item from the conversation.
struct ActionItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let detail: String
    let owner: String
    let priority: Priority
    var isCompleted: Bool

    enum Priority: String, Codable, CaseIterable {
        case high = "Haute"
        case medium = "Moyenne"
        case low = "Basse"
    }

    init(title: String, detail: String = "", owner: String = "Moi", priority: Priority = .medium) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.owner = owner
        self.priority = priority
        self.isCompleted = false
    }
}

// MARK: - Response Suggestion (Value Object)

/// A real-time response suggestion during conversation.
struct ResponseSuggestion: Identifiable {
    let id: UUID
    let text: String
    let context: SuggestionContext
    let confidence: Float
    let timestamp: TimeInterval

    init(text: String, context: SuggestionContext, confidence: Float = 0.8, timestamp: TimeInterval) {
        self.id = UUID()
        self.text = text
        self.context = context
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// Why this suggestion was generated.
enum SuggestionContext: String, Codable {
    case objectionHandling = "Traitement d'objection"
    case questionToAsk = "Question à poser"
    case closingOpportunity = "Opportunité de closing"
    case reengagement = "Réengagement"
    case valueProposition = "Proposition de valeur"
    case followUp = "Suivi"
    case general = "Suggestion"
}

// MARK: - Analytics Models (Value Objects)

/// Cross-session analytics insight.
struct ConversationInsight: Identifiable {
    let id: UUID
    let title: String
    let description: String
    let category: InsightCategory
    let impact: InsightImpact
    let dataPoints: Int

    init(title: String, description: String, category: InsightCategory, impact: InsightImpact, dataPoints: Int = 0) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.category = category
        self.impact = impact
        self.dataPoints = dataPoints
    }
}

enum InsightCategory: String, Codable {
    case pattern = "Pattern"
    case improvement = "Amélioration"
    case strength = "Force"
    case risk = "Risque"
}

enum InsightImpact: String, Codable {
    case high = "Fort"
    case medium = "Moyen"
    case low = "Faible"
}

/// Result of semantic search across sessions.
struct SemanticSearchResult: Identifiable {
    let id: UUID
    let sessionId: UUID
    let sessionTitle: String
    let matchingText: String
    let relevanceScore: Float
    let timestamp: Date
    let context: String

    init(sessionId: UUID, sessionTitle: String, matchingText: String, relevanceScore: Float, timestamp: Date, context: String = "") {
        self.id = UUID()
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.matchingText = matchingText
        self.relevanceScore = relevanceScore
        self.timestamp = timestamp
        self.context = context
    }
}
