import XCTest
@testable import VoiceScribe

// MARK: - SemanticSentimentAnalyzer Infrastructure Tests

final class SemanticSentimentAnalyzerTests: XCTestCase {

    var analyzer: SemanticSentimentAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = SemanticSentimentAnalyzer()
    }

    override func tearDown() {
        analyzer.reset()
        analyzer = nil
        super.tearDown()
    }

    // MARK: - Intent Detection

    func testDetectsQuestion() {
        let intent = analyzer.conversationIntent(from: "Combien ça coûte ?")
        XCTAssertEqual(intent, .asking)
    }

    func testDetectsObjection() {
        let intent = analyzer.conversationIntent(from: "C'est trop cher pour notre budget")
        XCTAssertEqual(intent, .objecting)
    }

    func testDetectsAgreement() {
        let intent = analyzer.conversationIntent(from: "Oui tout à fait, ça me convient parfaitement")
        XCTAssertEqual(intent, .agreeing)
    }

    func testDetectsCommitment() {
        let intent = analyzer.conversationIntent(from: "On signe quand ? Je suis prêt à avancer")
        XCTAssertEqual(intent, .committing)
    }

    func testDetectsDeflection() {
        let intent = analyzer.conversationIntent(from: "Il faut que j'en parle à mon directeur avant")
        XCTAssertEqual(intent, .deflecting)
    }

    func testDetectsNeutral() {
        let intent = analyzer.conversationIntent(from: "D'accord, je comprends")
        // Should be neutral or clarifying, not strongly positive/negative
        XCTAssertFalse(intent.isNegative)
    }

    // MARK: - Topic Detection

    func testDetectsPricingTopic() {
        let result = analyzer.analyze(text: "Quel est votre budget pour ce projet ?", speaker: .me, timestamp: 10.0)
        let pricingTopics = result.topics.filter { $0.category == .pricing }
        XCTAssertFalse(pricingTopics.isEmpty, "Should detect pricing topic from 'budget'")
    }

    func testDetectsCompetitorTopic() {
        let result = analyzer.analyze(text: "On utilise actuellement la solution de Salesforce", speaker: .other, timestamp: 10.0)
        let competitorTopics = result.topics.filter { $0.category == .competitor }
        XCTAssertFalse(competitorTopics.isEmpty, "Should detect competitor topic")
    }

    func testDetectsTimelineTopic() {
        let result = analyzer.analyze(text: "On doit déployer avant la fin du trimestre", speaker: .other, timestamp: 10.0)
        let timelineTopics = result.topics.filter { $0.category == .timeline }
        XCTAssertFalse(timelineTopics.isEmpty, "Should detect timeline topic")
    }

    func testDetectsDecisionTopic() {
        let result = analyzer.analyze(text: "Le directeur doit valider, c'est lui qui décide", speaker: .other, timestamp: 10.0)
        let decisionTopics = result.topics.filter { $0.category == .decision }
        XCTAssertFalse(decisionTopics.isEmpty, "Should detect decision topic")
    }

    func testDetectsPainTopic() {
        let result = analyzer.analyze(text: "Notre plus gros problème c'est la perte de temps sur les tâches manuelles", speaker: .other, timestamp: 10.0)
        let painTopics = result.topics.filter { $0.category == .pain }
        XCTAssertFalse(painTopics.isEmpty, "Should detect pain topic")
    }

    // MARK: - Sentiment Analysis

    func testPositiveSentiment() {
        let result = analyzer.analyze(text: "C'est excellent, exactement ce qu'il nous faut", speaker: .other, timestamp: 10.0)
        XCTAssertTrue(result.sentiment.isPositive, "Positive text should yield positive sentiment")
    }

    func testNegativeSentiment() {
        let result = analyzer.analyze(text: "Non ça ne nous intéresse pas du tout", speaker: .other, timestamp: 10.0)
        XCTAssertTrue(result.sentiment.isNegative, "Negative text should yield negative sentiment")
    }

    func testNeutralSentiment() {
        let result = analyzer.analyze(text: "On verra plus tard", speaker: .other, timestamp: 10.0)
        // Shouldn't be strongly positive
        XCTAssertFalse(result.sentiment.isPositive)
    }

    // MARK: - Topic Accumulation

    func testTopicsAccumulate() {
        _ = analyzer.analyze(text: "Le budget est de 50k", speaker: .other, timestamp: 10.0)
        _ = analyzer.analyze(text: "La deadline est fin mars", speaker: .other, timestamp: 20.0)
        let topics = analyzer.recentTopics()
        XCTAssertGreaterThanOrEqual(topics.count, 2)
    }

    func testResetClearsTopics() {
        _ = analyzer.analyze(text: "Le budget est serré", speaker: .other, timestamp: 10.0)
        XCTAssertFalse(analyzer.recentTopics().isEmpty)
        analyzer.reset()
        XCTAssertTrue(analyzer.recentTopics().isEmpty)
    }

    // MARK: - Certainty Detection

    func testHighCertainty() {
        let result = analyzer.analyze(text: "Je suis sûr que c'est la bonne solution", speaker: .other, timestamp: 10.0)
        XCTAssertGreaterThan(result.sentiment.certainty, 0.5, "Certain language should yield high certainty")
    }

    func testLowCertainty() {
        let result = analyzer.analyze(text: "Je ne sais pas trop, peut-être, on verra", speaker: .other, timestamp: 10.0)
        XCTAssertLessThan(result.sentiment.certainty, 0.5, "Uncertain language should yield low certainty")
    }

    // MARK: - Engagement Detection

    func testHighEngagement() {
        let result = analyzer.analyze(text: "C'est très intéressant, dites-m'en plus sur cette fonctionnalité", speaker: .other, timestamp: 10.0)
        XCTAssertGreaterThan(result.sentiment.engagement, 0.5, "Engaged language should yield high engagement")
    }

    func testLowEngagement() {
        let result = analyzer.analyze(text: "Bon ok", speaker: .other, timestamp: 10.0)
        XCTAssertLessThanOrEqual(result.sentiment.engagement, 0.6, "Short responses should yield lower engagement")
    }

    // MARK: - Confidence

    func testShortTextLowerConfidence() {
        let shortResult = analyzer.analyze(text: "Ok", speaker: .other, timestamp: 10.0)
        let longResult = analyzer.analyze(text: "Oui c'est exactement ce qu'il nous faut pour notre équipe de vente", speaker: .other, timestamp: 20.0)
        XCTAssertLessThan(shortResult.confidence, longResult.confidence, "Shorter text should have lower confidence")
    }
}

// MARK: - WebSocket STT Client Tests

final class WebSocketSTTClientTests: XCTestCase {

    func testInitialState() {
        let client = WebSocketSTTClient()
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testDisconnectFromDisconnected() {
        let client = WebSocketSTTClient()
        client.disconnect()
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testSendAudioWhileDisconnected() {
        let client = WebSocketSTTClient()
        // Should not crash when sending while disconnected
        client.sendAudio(samples: [0.1, 0.2, 0.3], timestamp: 0)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testCallbacksCanBeSet() {
        let client = WebSocketSTTClient()
        var partialReceived = false
        var finalReceived = false

        client.onPartialResult = { _ in partialReceived = true }
        client.onFinalResult = { _ in finalReceived = true }

        // Verify callbacks can be invoked
        client.onPartialResult?(PartialTranscription(text: "test", isFinal: false, timestamp: 0, backend: .voxtralWebSocket))
        client.onFinalResult?(PartialTranscription(text: "test", isFinal: true, timestamp: 0, backend: .voxtralWebSocket))

        XCTAssertTrue(partialReceived)
        XCTAssertTrue(finalReceived)
    }
}
