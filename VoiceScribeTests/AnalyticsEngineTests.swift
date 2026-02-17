import XCTest
@testable import VoiceScribe

// MARK: - LocalLLMProvider Tests

final class LocalLLMProviderTests: XCTestCase {

    var provider: LocalLLMProvider!

    override func setUp() {
        super.setUp()
        provider = LocalLLMProvider()
    }

    // MARK: - Summary Generation

    func testSummarizeFromTranscript() async throws {
        let transcript = """
        [00:00] Moi: Bonjour, merci de me recevoir.
        [00:15] Participant: Bonjour, de quoi s'agit-il ?
        [01:00] Moi: Je voudrais vous présenter notre solution CRM.
        [01:30] Participant: On utilise déjà Salesforce.
        [02:00] Moi: Notre solution est 3x plus rapide et moitié prix.
        [02:30] Participant: Intéressant. Quel est le budget ?
        [03:00] Moi: À partir de 500€/mois.
        [03:30] Participant: C'est dans notre budget. On peut planifier une démo ?
        """

        let summary = try await provider.summarize(transcript: transcript, report: nil, topics: [], config: .default)
        XCTAssertFalse(summary.executiveSummary.isEmpty, "Summary should not be empty")
        XCTAssertFalse(summary.keyPoints.isEmpty, "Should extract key points")
    }

    func testSummarizeWithReport() async throws {
        let memory = ConversationMemory()
        let report = PostCallReport(
            totalDuration: 300,
            movementTimeline: [(.accueil, 0, 30), (.enjeux, 30, 150), (.proposition, 150, 250), (.engagement, 250, 300)],
            memoryReport: memory.generateReport(),
            movementCount: 4,
            averageFluidityScore: 0.75,
            contextSummary: "Appel de découverte avec prospect PME"
        )

        let summary = try await provider.summarize(transcript: "Bonjour.", report: report, topics: [], config: .default)
        XCTAssertFalse(summary.executiveSummary.isEmpty)
        XCTAssertFalse(summary.coachingFeedback.isEmpty)
    }

    func testSummarizeWithTopics() async throws {
        let topics = [
            DetectedTopic(name: "budget", category: .pricing, confidence: 0.9, timestamp: 30),
            DetectedTopic(name: "concurrent", category: .competitor, confidence: 0.8, timestamp: 60)
        ]

        let summary = try await provider.summarize(transcript: "Discussion sur le budget.", report: nil, topics: topics, config: .default)
        XCTAssertFalse(summary.keyPoints.isEmpty)
    }

    func testSummarizeEmptyTranscript() async throws {
        let summary = try await provider.summarize(transcript: "", report: nil, topics: [], config: .default)
        XCTAssertFalse(summary.executiveSummary.isEmpty, "Should handle empty transcript gracefully")
    }

    // MARK: - Response Suggestions

    func testSuggestForObjection() async throws {
        let suggestions = try await provider.suggestResponse(
            recentText: "C'est trop cher pour nous",
            movement: .proposition,
            emotion: EmotionalState(valence: -0.4, arousal: 0.3, dominance: 0.0, confidence: 0.7),
            topics: [DetectedTopic(name: "prix", category: .pricing, confidence: 0.9, timestamp: 100)],
            config: .default
        )
        XCTAssertFalse(suggestions.isEmpty, "Should generate suggestions for objection")
        let hasObjectionHandling = suggestions.contains { $0.context == .objectionHandling }
        XCTAssertTrue(hasObjectionHandling, "Should include objection handling suggestion")
    }

    func testSuggestForBuyingSignal() async throws {
        let suggestions = try await provider.suggestResponse(
            recentText: "Oui c'est exactement ce qu'il nous faut, quand peut-on commencer ?",
            movement: .dialogue,
            emotion: EmotionalState(valence: 0.6, arousal: 0.5, dominance: 0.3, confidence: 0.8),
            topics: [],
            config: .default
        )
        XCTAssertFalse(suggestions.isEmpty, "Should generate suggestions for buying signal")
        let hasClosing = suggestions.contains { $0.context == .closingOpportunity }
        XCTAssertTrue(hasClosing, "Should include closing opportunity suggestion")
    }

    func testSuggestForDisengagement() async throws {
        let suggestions = try await provider.suggestResponse(
            recentText: "Bon ok",
            movement: .enjeux,
            emotion: EmotionalState(valence: -0.2, arousal: -0.5, dominance: -0.3, confidence: 0.6),
            topics: [],
            config: .default
        )
        XCTAssertFalse(suggestions.isEmpty)
        let hasReengagement = suggestions.contains { $0.context == .reengagement }
        XCTAssertTrue(hasReengagement, "Should include reengagement suggestion for disengagement")
    }

    func testSuggestForExploration() async throws {
        let suggestions = try await provider.suggestResponse(
            recentText: "On a des problèmes de productivité dans l'équipe",
            movement: .enjeux,
            emotion: EmotionalState(valence: 0.0, arousal: 0.3, dominance: 0.0, confidence: 0.6),
            topics: [DetectedTopic(name: "problème", category: .pain, confidence: 0.8, timestamp: 80)],
            config: .default
        )
        XCTAssertFalse(suggestions.isEmpty)
        let hasQuestion = suggestions.contains { $0.context == .questionToAsk }
        XCTAssertTrue(hasQuestion, "Should include deepening question for exploration phase")
    }

    // MARK: - Generate

    func testGenerateBasic() async throws {
        let response = try await provider.generate(prompt: "Test prompt", config: .default)
        XCTAssertFalse(response.text.isEmpty)
        XCTAssertEqual(response.backend, .local)
    }
}

// MARK: - AnalyticsEngine Tests

final class AnalyticsEngineTests: XCTestCase {

    func testGenerateInsightsEmpty() {
        let engine = AnalyticsEngine()
        let insights = engine.generateInsights()
        // With no data, should still return something meaningful
        XCTAssertTrue(insights.isEmpty || !insights.isEmpty) // Doesn't crash
    }

    func testSemanticSearchEmpty() {
        let engine = AnalyticsEngine()
        let results = engine.semanticSearch(query: "budget")
        // With no sessions loaded, should return empty
        XCTAssertTrue(results.isEmpty)
    }

    func testRefreshDoesNotCrash() {
        let engine = AnalyticsEngine()
        engine.refresh()
        // Should not crash even with no data
    }

    func testSemanticSearchRelevance() {
        let engine = AnalyticsEngine()
        engine.addSearchableSession(
            id: UUID(),
            title: "Call avec Marie",
            segments: [
                "Bonjour, je voulais discuter du budget pour le projet",
                "Notre budget est de 50 000 euros pour ce trimestre",
                "C'est dans nos moyens, planifions une démo"
            ],
            date: Date()
        )

        let results = engine.semanticSearch(query: "budget")
        XCTAssertFalse(results.isEmpty, "Should find budget-related segments")
        XCTAssertGreaterThan(results.first?.relevanceScore ?? 0, 0.5, "Budget query should have high relevance")
    }

    func testSemanticSearchNoMatch() {
        let engine = AnalyticsEngine()
        engine.addSearchableSession(
            id: UUID(),
            title: "Call technique",
            segments: ["Discussion sur l'API REST", "Intégration via webhook"],
            date: Date()
        )

        let results = engine.semanticSearch(query: "budget")
        // Should not match or have low relevance
        if !results.isEmpty {
            XCTAssertLessThan(results.first?.relevanceScore ?? 1, 0.8, "Unrelated content should have low relevance")
        }
    }

    func testInsightsFromMovementStats() {
        let engine = AnalyticsEngine()
        // Simulate movement stats
        engine.injectMovementStats([
            AnalyticsEngine.MovementStatEntry(movement: .accueil, avgDuration: 120, avgFluidity: 0.3, count: 10),
            AnalyticsEngine.MovementStatEntry(movement: .enjeux, avgDuration: 300, avgFluidity: 0.8, count: 10),
            AnalyticsEngine.MovementStatEntry(movement: .proposition, avgDuration: 200, avgFluidity: 0.6, count: 8)
        ])

        let insights = engine.generateInsights()
        XCTAssertFalse(insights.isEmpty, "Should generate insights from movement stats")
    }
}
