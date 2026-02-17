import XCTest
@testable import VoiceScribe

// MARK: - LLMBackend Tests

final class LLMBackendTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(LLMBackend.allCases.count, 3)
    }

    func testIsLocal() {
        XCTAssertTrue(LLMBackend.local.isLocal)
        XCTAssertFalse(LLMBackend.claudeAPI.isLocal)
        XCTAssertFalse(LLMBackend.openAIAPI.isLocal)
    }

    func testRequiresAPIKey() {
        XCTAssertFalse(LLMBackend.local.requiresAPIKey)
        XCTAssertTrue(LLMBackend.claudeAPI.requiresAPIKey)
        XCTAssertTrue(LLMBackend.openAIAPI.requiresAPIKey)
    }

    func testDisplayNames() {
        for backend in LLMBackend.allCases {
            XCTAssertFalse(backend.displayName.isEmpty)
        }
    }
}

// MARK: - LLMConfig Tests

final class LLMConfigTests: XCTestCase {

    func testDefaults() {
        let config = LLMConfig.default
        XCTAssertEqual(config.backend, .local)
        XCTAssertTrue(config.apiKey.isEmpty)
        XCTAssertEqual(config.maxTokens, 1024)
        XCTAssertEqual(config.temperature, 0.3)
    }

    func testEquality() {
        XCTAssertEqual(LLMConfig.default, LLMConfig.default)
        let modified = LLMConfig(backend: .claudeAPI)
        XCTAssertNotEqual(LLMConfig.default, modified)
    }
}

// MARK: - LLMResponse Tests

final class LLMResponseTests: XCTestCase {

    func testCreation() {
        let response = LLMResponse(text: "Test output", tokensUsed: 50, latencyMs: 200, backend: .local)
        XCTAssertEqual(response.text, "Test output")
        XCTAssertEqual(response.tokensUsed, 50)
        XCTAssertEqual(response.latencyMs, 200)
        XCTAssertEqual(response.backend, .local)
    }

    func testDefaults() {
        let response = LLMResponse(text: "Hello", backend: .claudeAPI)
        XCTAssertEqual(response.tokensUsed, 0)
        XCTAssertEqual(response.latencyMs, 0)
    }
}

// MARK: - SessionSummary Tests

final class SessionSummaryTests: XCTestCase {

    func testCreation() {
        let summary = SessionSummary(
            sessionId: UUID(),
            backend: .local,
            executiveSummary: "Call went well",
            keyPoints: ["Point 1", "Point 2"],
            actionItems: [ActionItem(title: "Follow up")],
            sentimentArc: "Positive throughout",
            nextSteps: "Schedule demo",
            coachingFeedback: "Good job"
        )
        XCTAssertEqual(summary.keyPoints.count, 2)
        XCTAssertEqual(summary.actionItems.count, 1)
        XCTAssertEqual(summary.backend, .local)
    }

    func testUniqueIds() {
        let a = SessionSummary(sessionId: UUID(), backend: .local, executiveSummary: "", keyPoints: [], actionItems: [], sentimentArc: "", nextSteps: "", coachingFeedback: "")
        let b = SessionSummary(sessionId: UUID(), backend: .local, executiveSummary: "", keyPoints: [], actionItems: [], sentimentArc: "", nextSteps: "", coachingFeedback: "")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testToMarkdown() {
        let summary = SessionSummary(
            sessionId: UUID(),
            backend: .local,
            executiveSummary: "Un appel productif.",
            keyPoints: ["Budget identifié", "Timeline claire"],
            actionItems: [ActionItem(title: "Envoyer devis", owner: "Moi")],
            sentimentArc: "Positif → très positif",
            nextSteps: "Planifier une démo",
            coachingFeedback: "Bon découverte"
        )
        let md = summary.toMarkdown()
        XCTAssertTrue(md.contains("Synthèse IA"))
        XCTAssertTrue(md.contains("Un appel productif"))
        XCTAssertTrue(md.contains("Budget identifié"))
        XCTAssertTrue(md.contains("Envoyer devis"))
        XCTAssertTrue(md.contains("Positif"))
        XCTAssertTrue(md.contains("Planifier une démo"))
    }
}

// MARK: - ActionItem Tests

final class ActionItemTests: XCTestCase {

    func testCreation() {
        let item = ActionItem(title: "Follow up", detail: "Send proposal", owner: "Marie", priority: .high)
        XCTAssertEqual(item.title, "Follow up")
        XCTAssertEqual(item.detail, "Send proposal")
        XCTAssertEqual(item.owner, "Marie")
        XCTAssertEqual(item.priority, .high)
        XCTAssertFalse(item.isCompleted)
    }

    func testDefaults() {
        let item = ActionItem(title: "Test")
        XCTAssertEqual(item.owner, "Moi")
        XCTAssertEqual(item.priority, .medium)
        XCTAssertTrue(item.detail.isEmpty)
    }

    func testCompletion() {
        var item = ActionItem(title: "Test")
        XCTAssertFalse(item.isCompleted)
        item.isCompleted = true
        XCTAssertTrue(item.isCompleted)
    }

    func testUniqueIds() {
        let a = ActionItem(title: "A")
        let b = ActionItem(title: "B")
        XCTAssertNotEqual(a.id, b.id)
    }
}

// MARK: - ResponseSuggestion Tests

final class ResponseSuggestionTests: XCTestCase {

    func testCreation() {
        let suggestion = ResponseSuggestion(
            text: "Quel est votre budget ?",
            context: .questionToAsk,
            confidence: 0.9,
            timestamp: 120.0
        )
        XCTAssertEqual(suggestion.text, "Quel est votre budget ?")
        XCTAssertEqual(suggestion.context, .questionToAsk)
        XCTAssertEqual(suggestion.confidence, 0.9)
        XCTAssertEqual(suggestion.timestamp, 120.0)
    }

    func testDefaultConfidence() {
        let suggestion = ResponseSuggestion(text: "Test", context: .general, timestamp: 0)
        XCTAssertEqual(suggestion.confidence, 0.8)
    }

    func testUniqueIds() {
        let a = ResponseSuggestion(text: "A", context: .general, timestamp: 0)
        let b = ResponseSuggestion(text: "B", context: .general, timestamp: 0)
        XCTAssertNotEqual(a.id, b.id)
    }
}

// MARK: - SuggestionContext Tests

final class SuggestionContextTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(SuggestionContext.objectionHandling.rawValue, "Traitement d'objection")
        XCTAssertEqual(SuggestionContext.closingOpportunity.rawValue, "Opportunité de closing")
    }
}

// MARK: - ConversationInsight Tests

final class ConversationInsightTests: XCTestCase {

    func testCreation() {
        let insight = ConversationInsight(
            title: "Trop de temps en accueil",
            description: "Moyenne 3x supérieure au benchmark",
            category: .improvement,
            impact: .high,
            dataPoints: 15
        )
        XCTAssertEqual(insight.title, "Trop de temps en accueil")
        XCTAssertEqual(insight.category, .improvement)
        XCTAssertEqual(insight.impact, .high)
        XCTAssertEqual(insight.dataPoints, 15)
    }
}

// MARK: - SemanticSearchResult Tests

final class SemanticSearchResultTests: XCTestCase {

    func testCreation() {
        let result = SemanticSearchResult(
            sessionId: UUID(),
            sessionTitle: "Call avec Marie",
            matchingText: "budget de 50k",
            relevanceScore: 0.95,
            timestamp: Date()
        )
        XCTAssertEqual(result.sessionTitle, "Call avec Marie")
        XCTAssertEqual(result.matchingText, "budget de 50k")
        XCTAssertEqual(result.relevanceScore, 0.95)
    }
}

// MARK: - Mock LLM Provider (for protocol contract tests)

final class MockLLMProvider: LLMProvider {
    var generateCallCount = 0
    var summarizeCallCount = 0
    var suggestCallCount = 0

    func generate(prompt: String, config: LLMConfig) async throws -> LLMResponse {
        generateCallCount += 1
        return LLMResponse(text: "Mock response for: \(prompt.prefix(30))", backend: config.backend)
    }

    func summarize(transcript: String, report: PostCallReport?, topics: [DetectedTopic], config: LLMConfig) async throws -> SessionSummary {
        summarizeCallCount += 1
        return SessionSummary(
            sessionId: UUID(),
            backend: config.backend,
            executiveSummary: "Résumé mock de la session",
            keyPoints: ["Point 1", "Point 2"],
            actionItems: [ActionItem(title: "Action mock")],
            sentimentArc: "Neutre → Positif",
            nextSteps: "Planifier un suivi",
            coachingFeedback: "Bonne session"
        )
    }

    func suggestResponse(recentText: String, movement: ConversationMovement, emotion: EmotionalState, topics: [DetectedTopic], config: LLMConfig) async throws -> [ResponseSuggestion] {
        suggestCallCount += 1
        return [
            ResponseSuggestion(text: "Suggestion mock 1", context: .questionToAsk, timestamp: 0),
            ResponseSuggestion(text: "Suggestion mock 2", context: .objectionHandling, timestamp: 0)
        ]
    }
}

final class LLMProviderContractTests: XCTestCase {

    func testGenerate() async throws {
        let provider = MockLLMProvider()
        let response = try await provider.generate(prompt: "Test prompt", config: .default)
        XCTAssertFalse(response.text.isEmpty)
        XCTAssertEqual(provider.generateCallCount, 1)
    }

    func testSummarize() async throws {
        let provider = MockLLMProvider()
        let summary = try await provider.summarize(transcript: "Test transcript", report: nil, topics: [], config: .default)
        XCTAssertFalse(summary.executiveSummary.isEmpty)
        XCTAssertFalse(summary.keyPoints.isEmpty)
        XCTAssertEqual(provider.summarizeCallCount, 1)
    }

    func testSuggestResponse() async throws {
        let provider = MockLLMProvider()
        let suggestions = try await provider.suggestResponse(
            recentText: "C'est trop cher",
            movement: .proposition,
            emotion: EmotionalState(valence: -0.3, arousal: 0.4, dominance: 0.0, confidence: 0.7),
            topics: [],
            config: .default
        )
        XCTAssertGreaterThanOrEqual(suggestions.count, 1)
        XCTAssertEqual(provider.suggestCallCount, 1)
    }
}

// MARK: - Mock Analytics Provider

final class MockAnalyticsProvider: AnalyticsProvider {
    var refreshCallCount = 0

    func generateInsights() -> [ConversationInsight] {
        [ConversationInsight(title: "Mock insight", description: "Test", category: .pattern, impact: .medium)]
    }

    func semanticSearch(query: String) -> [SemanticSearchResult] {
        [SemanticSearchResult(sessionId: UUID(), sessionTitle: "Mock session", matchingText: query, relevanceScore: 0.9, timestamp: Date())]
    }

    func refresh() { refreshCallCount += 1 }
}

final class AnalyticsProviderContractTests: XCTestCase {

    func testGenerateInsights() {
        let provider = MockAnalyticsProvider()
        let insights = provider.generateInsights()
        XCTAssertFalse(insights.isEmpty)
    }

    func testSemanticSearch() {
        let provider = MockAnalyticsProvider()
        let results = provider.semanticSearch(query: "budget")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.matchingText.contains("budget") ?? false)
    }

    func testRefresh() {
        let provider = MockAnalyticsProvider()
        provider.refresh()
        XCTAssertEqual(provider.refreshCallCount, 1)
    }
}
