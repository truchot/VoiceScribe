import XCTest
@testable import VoiceScribe

// MARK: - SemanticSentiment Tests

final class SemanticSentimentTests: XCTestCase {

    func testDefaults() {
        let sentiment = SemanticSentiment()
        XCTAssertEqual(sentiment.polarity, 0.0)
        XCTAssertEqual(sentiment.certainty, 0.5)
        XCTAssertEqual(sentiment.formality, 0.5)
        XCTAssertEqual(sentiment.engagement, 0.5)
    }

    func testIsPositive() {
        let positive = SemanticSentiment(polarity: 0.5)
        XCTAssertTrue(positive.isPositive)
        XCTAssertFalse(positive.isNegative)
        XCTAssertFalse(positive.isNeutral)
    }

    func testIsNegative() {
        let negative = SemanticSentiment(polarity: -0.5)
        XCTAssertTrue(negative.isNegative)
        XCTAssertFalse(negative.isPositive)
    }

    func testIsNeutral() {
        let neutral = SemanticSentiment(polarity: 0.1)
        XCTAssertTrue(neutral.isNeutral)
        XCTAssertFalse(neutral.isPositive)
        XCTAssertFalse(neutral.isNegative)
    }

    func testEquality() {
        let a = SemanticSentiment(polarity: 0.5, certainty: 0.8)
        let b = SemanticSentiment(polarity: 0.5, certainty: 0.8)
        XCTAssertEqual(a, b)
    }
}

// MARK: - SemanticAnalysis Tests

final class SemanticAnalysisTests: XCTestCase {

    func testEmpty() {
        let analysis = SemanticAnalysis.empty(at: 10.0)
        XCTAssertTrue(analysis.topics.isEmpty)
        XCTAssertEqual(analysis.intent, .neutral)
        XCTAssertEqual(analysis.confidence, 0)
        XCTAssertEqual(analysis.timestamp, 10.0)
    }

    func testWithData() {
        let topic = DetectedTopic(name: "budget", category: .pricing, confidence: 0.9, timestamp: 5.0)
        let analysis = SemanticAnalysis(
            sentiment: SemanticSentiment(polarity: -0.3),
            topics: [topic],
            intent: .objecting,
            confidence: 0.85,
            timestamp: 5.0
        )
        XCTAssertEqual(analysis.topics.count, 1)
        XCTAssertEqual(analysis.intent, .objecting)
        XCTAssertTrue(analysis.sentiment.isNegative)
    }
}

// MARK: - DetectedTopic Tests

final class DetectedTopicTests: XCTestCase {

    func testCreation() {
        let topic = DetectedTopic(name: "prix", category: .pricing, confidence: 0.8, timestamp: 10.0)
        XCTAssertEqual(topic.name, "prix")
        XCTAssertEqual(topic.category, .pricing)
        XCTAssertEqual(topic.confidence, 0.8)
        XCTAssertEqual(topic.firstMentionTime, 10.0)
        XCTAssertEqual(topic.mentionCount, 1)
    }

    func testIncrementMention() {
        var topic = DetectedTopic(name: "budget", category: .pricing, confidence: 0.9, timestamp: 5.0)
        topic.incrementMention()
        topic.incrementMention()
        XCTAssertEqual(topic.mentionCount, 3)
    }

    func testUniqueIds() {
        let a = DetectedTopic(name: "a", category: .general, confidence: 0.5, timestamp: 0)
        let b = DetectedTopic(name: "a", category: .general, confidence: 0.5, timestamp: 0)
        XCTAssertNotEqual(a.id, b.id)
    }
}

// MARK: - TopicCategory Tests

final class TopicCategoryTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(TopicCategory.allCases.count, 8)
    }

    func testRawValues() {
        XCTAssertEqual(TopicCategory.pricing.rawValue, "Prix")
        XCTAssertEqual(TopicCategory.competitor.rawValue, "Concurrent")
        XCTAssertEqual(TopicCategory.decision.rawValue, "Décision")
    }
}

// MARK: - ConversationalIntent Tests

final class ConversationalIntentTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(ConversationalIntent.allCases.count, 8)
    }

    func testPositiveIntents() {
        XCTAssertTrue(ConversationalIntent.agreeing.isPositive)
        XCTAssertTrue(ConversationalIntent.committing.isPositive)
        XCTAssertTrue(ConversationalIntent.asking.isPositive)
        XCTAssertFalse(ConversationalIntent.objecting.isPositive)
    }

    func testNegativeIntents() {
        XCTAssertTrue(ConversationalIntent.objecting.isNegative)
        XCTAssertTrue(ConversationalIntent.deflecting.isNegative)
        XCTAssertFalse(ConversationalIntent.agreeing.isNegative)
        XCTAssertFalse(ConversationalIntent.neutral.isNegative)
    }

    func testRawValues() {
        XCTAssertEqual(ConversationalIntent.asking.rawValue, "Question")
        XCTAssertEqual(ConversationalIntent.objecting.rawValue, "Objection")
        XCTAssertEqual(ConversationalIntent.committing.rawValue, "Engagement")
    }
}

// MARK: - Mock Semantic Sentiment Provider (for protocol contract tests)

final class MockSemanticSentiment: SemanticSentimentProvider {
    private var topics: [DetectedTopic] = []
    private var analyzeCallCount = 0

    func analyze(text: String, speaker: Speaker, timestamp: TimeInterval) -> SemanticAnalysis {
        analyzeCallCount += 1

        // Simple mock: detect "budget" → pricing topic, "non" → objection
        var detectedTopics: [DetectedTopic] = []
        var intent: ConversationalIntent = .neutral
        var polarity: Float = 0.0

        let lower = text.lowercased()
        if lower.contains("budget") || lower.contains("prix") {
            detectedTopics.append(DetectedTopic(name: "budget", category: .pricing, confidence: 0.9, timestamp: timestamp))
        }
        if lower.contains("non") || lower.contains("trop cher") {
            intent = .objecting
            polarity = -0.5
        }
        if lower.contains("oui") || lower.contains("parfait") {
            intent = .agreeing
            polarity = 0.5
        }
        if lower.contains("?") {
            intent = .asking
        }

        topics.append(contentsOf: detectedTopics)

        return SemanticAnalysis(
            sentiment: SemanticSentiment(polarity: polarity),
            topics: detectedTopics,
            intent: intent,
            confidence: 0.8,
            timestamp: timestamp
        )
    }

    func recentTopics() -> [DetectedTopic] { topics }

    func conversationIntent(from text: String) -> ConversationalIntent {
        let lower = text.lowercased()
        if lower.contains("?") { return .asking }
        if lower.contains("non") { return .objecting }
        if lower.contains("oui") { return .agreeing }
        return .neutral
    }

    func reset() {
        topics.removeAll()
        analyzeCallCount = 0
    }
}

final class SemanticSentimentContractTests: XCTestCase {

    func testAnalyzeDetectsObjection() {
        let provider = MockSemanticSentiment()
        let result = provider.analyze(text: "C'est trop cher pour nous", speaker: .other, timestamp: 10.0)
        XCTAssertEqual(result.intent, .objecting)
        XCTAssertTrue(result.sentiment.isNegative)
    }

    func testAnalyzeDetectsAgreement() {
        let provider = MockSemanticSentiment()
        let result = provider.analyze(text: "Oui c'est parfait", speaker: .other, timestamp: 15.0)
        XCTAssertEqual(result.intent, .agreeing)
        XCTAssertTrue(result.sentiment.isPositive)
    }

    func testAnalyzeDetectsPricingTopic() {
        let provider = MockSemanticSentiment()
        let result = provider.analyze(text: "Quel est votre budget pour ce projet ?", speaker: .me, timestamp: 20.0)
        XCTAssertEqual(result.topics.count, 1)
        XCTAssertEqual(result.topics.first?.category, .pricing)
    }

    func testRecentTopicsAccumulate() {
        let provider = MockSemanticSentiment()
        _ = provider.analyze(text: "Le budget est de 50k", speaker: .other, timestamp: 10.0)
        _ = provider.analyze(text: "Le prix est important", speaker: .other, timestamp: 20.0)
        XCTAssertEqual(provider.recentTopics().count, 2)
    }

    func testResetClearsState() {
        let provider = MockSemanticSentiment()
        _ = provider.analyze(text: "Le budget est serré", speaker: .other, timestamp: 10.0)
        XCTAssertFalse(provider.recentTopics().isEmpty)
        provider.reset()
        XCTAssertTrue(provider.recentTopics().isEmpty)
    }

    func testConversationIntent() {
        let provider = MockSemanticSentiment()
        XCTAssertEqual(provider.conversationIntent(from: "Combien ça coûte ?"), .asking)
        XCTAssertEqual(provider.conversationIntent(from: "Non merci"), .objecting)
        XCTAssertEqual(provider.conversationIntent(from: "Oui allons-y"), .agreeing)
        XCTAssertEqual(provider.conversationIntent(from: "D'accord"), .neutral)
    }
}
