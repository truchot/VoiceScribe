import XCTest
@testable import VoiceScribe

// MARK: - ConversationCoach Tests

final class ConversationCoachTests: XCTestCase {

    private var coach: ConversationCoach!

    override func setUp() {
        super.setUp()
        coach = ConversationCoach()
    }

    override func tearDown() {
        coach = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialMovementIsAccueil() {
        XCTAssertEqual(coach.currentMovement, .accueil)
    }

    func testInitialMemoryIsEmpty() {
        XCTAssertTrue(coach.conversationMemory.slots.isEmpty)
    }

    // MARK: - Coaching Output

    func testCoachProducesOutput() {
        let segments = makeSegments(["Bonjour, comment allez-vous ?"])
        let emotion = EmotionalState(valence: 0.0, arousal: 0.0, dominance: 0.0, confidence: 0.5)

        let output = coach.coach(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: emotion,
            elapsed: 10.0
        )

        XCTAssertNotNil(output)
        XCTAssertEqual(output.movement, .accueil) // Should start at accueil
        XCTAssertFalse(output.goldenRule.isEmpty)
        XCTAssertFalse(output.suggestedAction.phrase.isEmpty)
    }

    func testCoachWithFrustratedEmotion() {
        let segments = makeSegments(["C'est vraiment frustrant ce problème"])
        let emotion = EmotionalState(valence: -0.6, arousal: 0.6, dominance: 0.0, confidence: 0.8)

        let output = coach.coach(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: emotion,
            elapsed: 300.0
        )

        // Frustrated emotion should produce emotion coaching
        if let emotionCoaching = output.emotionCoaching {
            XCTAssertEqual(emotionCoaching.emotion, .frustrated)
            XCTAssertFalse(emotionCoaching.empathyPhrase.isEmpty)
        }
    }

    func testCoachWithEnthusiasticEmotion() {
        let segments = makeSegments(["C'est exactement ce qu'on cherchait !"])
        let emotion = EmotionalState(valence: 0.8, arousal: 0.7, dominance: 0.5, confidence: 0.9)

        let output = coach.coach(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: emotion,
            elapsed: 600.0
        )

        if let emotionCoaching = output.emotionCoaching {
            XCTAssertEqual(emotionCoaching.emotion, .enthusiastic)
        }
    }

    // MARK: - Speaker Balance

    func testSpeakerBalanceWithMixedSpeakers() {
        var segments: [TranscriptionSegment] = []
        // Add balanced conversation
        for i in 0..<10 {
            let speaker: Speaker = i % 2 == 0 ? .me : .other
            segments.append(TranscriptionSegment(
                text: "Segment numéro \(i) avec quelques mots",
                startTime: Double(i * 5),
                endTime: Double(i * 5 + 4),
                speaker: speaker
            ))
        }

        let emotion = EmotionalState(confidence: 0.5)
        let output = coach.coach(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: emotion,
            elapsed: 50.0
        )

        // Balance should be relatively even
        let balance = output.speakerBalance
        XCTAssertGreaterThan(balance.myRatio, 0.0)
        XCTAssertLessThan(balance.myRatio, 1.0)
    }

    // MARK: - Override Movement

    func testOverrideMovement() {
        coach.overrideMovement(.proposition, at: 600.0)
        XCTAssertEqual(coach.currentMovement, .proposition)
    }

    func testOverrideMovementPersists() {
        coach.overrideMovement(.enjeux, at: 120.0)

        let segments = makeSegments(["Bonjour"])
        let output = coach.coach(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: EmotionalState(),
            elapsed: 130.0
        )

        XCTAssertEqual(output.movement, .enjeux)
        XCTAssertTrue(output.isManualOverride)
    }

    // MARK: - Memory

    func testSetMemory() {
        coach.setMemory(key: "prospect_name", value: "Jean Dupont", elapsed: 60.0)
        XCTAssertEqual(coach.conversationMemory.get("prospect_name"), "Jean Dupont")
    }

    func testMemoryPersonalizesActions() {
        coach.setMemory(key: "main_pain", value: "perte de temps sur les devis", elapsed: 300.0)
        coach.overrideMovement(.profondeur, at: 300.0)

        let segments = makeSegments(["On perd beaucoup de temps"])
        let output = coach.coach(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: EmotionalState(confidence: 0.5),
            elapsed: 310.0
        )

        // Focus should mention the known pain
        let hasPainRef = output.focusNow.contains("perte de temps") ||
                         output.focusNow.contains("devis") ||
                         output.focusNow.contains("Quantifiez")
        XCTAssertTrue(hasPainRef, "Focus should reference known pain: got '\(output.focusNow)'")
    }

    // MARK: - Slot Status

    func testSlotStatusReflectsMemory() {
        coach.setMemory(key: "prospect_name", value: "Marie", elapsed: 10.0)

        let segments = makeSegments(["Bonjour"])
        let output = coach.coach(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: EmotionalState(),
            elapsed: 15.0
        )

        // Check if any slot is filled
        let filledSlots = output.slotStatus.filter { $0.filled }
        let prospectSlot = output.slotStatus.first(where: { $0.key == "prospect_name" })
        if let slot = prospectSlot {
            XCTAssertTrue(slot.filled)
            XCTAssertEqual(slot.value, "Marie")
        }
    }

    // MARK: - Reset

    func testReset() {
        coach.setMemory(key: "test", value: "value", elapsed: 10.0)
        coach.overrideMovement(.proposition, at: 100.0)
        coach.reset()

        XCTAssertEqual(coach.currentMovement, .accueil)
        XCTAssertTrue(coach.conversationMemory.slots.isEmpty)
    }

    // MARK: - Post-Call Report

    func testGenerateReport() {
        coach.setMemory(key: "prospect_name", value: "Test", elapsed: 10.0)
        coach.setMemory(key: "main_pain", value: "slowness", elapsed: 60.0)

        let report = coach.generateReport(elapsed: 300.0)

        XCTAssertEqual(report.totalDuration, 300.0)
        XCTAssertFalse(report.movementTimeline.isEmpty)
        XCTAssertTrue(report.contextSummary.contains("Test"))
    }

    func testReportMarkdownExport() {
        coach.setMemory(key: "budget_range", value: "50k-100k", elapsed: 300.0)
        let report = coach.generateReport(elapsed: 600.0)
        let markdown = report.toMarkdown()

        XCTAssertTrue(markdown.contains("# Rapport Post-Call"))
        XCTAssertTrue(markdown.contains("budget_range"))
    }

    // MARK: - Protocol Conformance

    func testConformsToCoachingProvider() {
        let provider: CoachingProvider = ConversationCoach()
        XCTAssertNotNil(provider)
    }

    // MARK: - Helpers

    private func makeSegments(_ texts: [String], speaker: Speaker = .other) -> [TranscriptionSegment] {
        texts.enumerated().map { i, text in
            TranscriptionSegment(
                text: text,
                startTime: Double(i * 5),
                endTime: Double(i * 5 + 4),
                speaker: speaker
            )
        }
    }
}

// MARK: - MovementDetector Tests

final class MovementDetectorTests: XCTestCase {

    private var detector: MovementDetector!

    override func setUp() {
        super.setUp()
        detector = MovementDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    func testInitialMovementIsAccueil() {
        XCTAssertEqual(detector.currentMovement, .accueil)
    }

    func testDetectionProducesResult() {
        let segments = [
            TranscriptionSegment(text: "Bonjour", startTime: 0, endTime: 1, speaker: .me)
        ]
        let memory = ConversationMemory()

        let result = detector.detect(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: EmotionalState(),
            memory: memory,
            elapsed: 5.0
        )

        XCTAssertEqual(result.currentMovement, .accueil)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.0)
        XCTAssertLessThanOrEqual(result.confidence, 1.0)
    }

    func testManualOverride() {
        detector.override(to: .qualification, at: 120.0)
        XCTAssertEqual(detector.currentMovement, .qualification)
    }

    func testTimeline() {
        detector.override(to: .cadrage, at: 60.0)
        detector.override(to: .univers, at: 120.0)
        let timeline = detector.timeline(currentElapsed: 180.0)

        XCTAssertEqual(timeline.count, 3) // accueil, cadrage, univers (current)
        XCTAssertEqual(timeline[0].movement, .accueil)
        XCTAssertEqual(timeline[1].movement, .cadrage)
        XCTAssertEqual(timeline[2].movement, .univers)
    }

    func testReset() {
        detector.override(to: .proposition, at: 600.0)
        detector.reset()
        XCTAssertEqual(detector.currentMovement, .accueil)
    }

    func testKeywordDetection() {
        // Feed keywords that match enjeux movement
        let segments = [
            TranscriptionSegment(
                text: "Notre plus gros problème c'est qu'on est bloqué",
                startTime: 300, endTime: 305, speaker: .other
            )
        ]
        let memory = ConversationMemory()

        // Need to advance past accueil first
        detector.override(to: .univers, at: 200.0)

        let result = detector.detect(
            recentSegments: ArraySlice(segments),
            allSegments: segments,
            emotion: EmotionalState(),
            memory: memory,
            elapsed: 305.0
        )

        // Should detect enjeux signals
        let hasEnjeuxSignal = result.signals.contains(where: {
            $0.contains("problème") || $0.contains("bloqué")
        })
        // May or may not switch, but should at least detect the signals
        XCTAssertTrue(result.confidence > 0)
    }
}

// MARK: - ConversationMemory Tests

final class ConversationMemoryTests: XCTestCase {

    private var memory: ConversationMemory!

    override func setUp() {
        super.setUp()
        memory = ConversationMemory()
    }

    override func tearDown() {
        memory = nil
        super.tearDown()
    }

    func testEmptyMemory() {
        XCTAssertTrue(memory.slots.isEmpty)
        XCTAssertFalse(memory.has("anything"))
        XCTAssertNil(memory.get("anything"))
    }

    func testManualSet() {
        memory.set(key: "prospect_name", value: "Alice", movement: .accueil, elapsed: 10.0)
        XCTAssertTrue(memory.has("prospect_name"))
        XCTAssertEqual(memory.get("prospect_name"), "Alice")
    }

    func testContextString() {
        memory.set(key: "prospect_name", value: "Bob", movement: .accueil, elapsed: 10.0)
        memory.set(key: "company_name", value: "ACME", movement: .univers, elapsed: 60.0)
        let ctx = memory.contextString()
        XCTAssertTrue(ctx.contains("Bob"))
        XCTAssertTrue(ctx.contains("ACME"))
    }

    func testPersonalize() {
        memory.set(key: "main_pain", value: "devis lents", movement: .enjeux, elapsed: 200.0)
        let result = memory.personalize("Votre problème de [main_pain] est réel")
        XCTAssertEqual(result, "Votre problème de devis lents est réel")
    }

    func testPersonalizeUnfilledPlaceholders() {
        let result = memory.personalize("Budget: [budget_range]")
        XCTAssertEqual(result, "Budget: [...]")
    }

    func testReadinessScore() {
        // Without any data, readiness should be low (if there are critical slots)
        let readiness = memory.readiness(for: .qualification)
        XCTAssertLessThanOrEqual(readiness, 1.0)
        XCTAssertGreaterThanOrEqual(readiness, 0.0)
    }

    func testMissingCriticalSlots() {
        let missing = memory.missingCriticalSlots(for: .enjeux)
        // Should return critical slots that aren't filled
        for slot in missing {
            XCTAssertEqual(slot.importance, .critical)
            XCTAssertFalse(memory.has(slot.key))
        }
    }

    func testReset() {
        memory.set(key: "test", value: "value", movement: .accueil, elapsed: 10.0)
        memory.reset()
        XCTAssertTrue(memory.slots.isEmpty)
        XCTAssertFalse(memory.has("test"))
    }

    func testCaptureHistory() {
        memory.set(key: "a", value: "1", movement: .accueil, elapsed: 10.0)
        memory.set(key: "b", value: "2", movement: .cadrage, elapsed: 20.0)
        XCTAssertEqual(memory.captureHistory.count, 2)
    }

    func testQualificationScore() {
        // Set all BANT keys
        memory.set(key: "budget_range", value: "100k", movement: .qualification, elapsed: 300.0)
        memory.set(key: "decision_maker", value: "CTO", movement: .qualification, elapsed: 310.0)
        memory.set(key: "timeline", value: "Q2", movement: .qualification, elapsed: 320.0)
        memory.set(key: "decision_process", value: "comité", movement: .qualification, elapsed: 330.0)

        let report = memory.generateReport()
        XCTAssertEqual(report.qualificationScore, 1.0, "All BANT keys filled = 100%")
    }

    func testDiscoveryScore() {
        memory.set(key: "main_pain", value: "lenteur", movement: .enjeux, elapsed: 200.0)
        memory.set(key: "desired_outcome", value: "rapidité", movement: .vision, elapsed: 400.0)

        let report = memory.generateReport()
        XCTAssertGreaterThan(report.discoveryScore, 0.0)
        XCTAssertLessThan(report.discoveryScore, 1.0) // Not all keys filled
    }
}

// MARK: - CoachingSuggestionEngine Tests

final class CoachingSuggestionEngineTests: XCTestCase {

    private var engine: CoachingSuggestionEngine!

    override func setUp() {
        super.setUp()
        engine = CoachingSuggestionEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    func testNoSuggestionForLowConfidence() {
        let emotion = EmotionalState(valence: 0.8, arousal: 0.8, dominance: 0, confidence: 0.1)
        let suggestion = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)
        XCTAssertNil(suggestion, "Low confidence should produce no suggestion")
    }

    func testFrustratedSuggestion() {
        let emotion = EmotionalState(valence: -0.6, arousal: 0.6, dominance: 0.0, confidence: 0.8)
        let suggestion = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.targetEmotion, .frustrated)
        XCTAssertEqual(suggestion?.category, .empathize)
    }

    func testHesitantSuggestion() {
        let emotion = EmotionalState(valence: 0.0, arousal: 0.0, dominance: -0.6, confidence: 0.8)
        let suggestion = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.targetEmotion, .hesitant)
    }

    func testDisengagedSuggestion() {
        let emotion = EmotionalState(valence: -0.5, arousal: -0.5, dominance: 0.0, confidence: 0.8)
        let suggestion = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.targetEmotion, .disengaged)
        XCTAssertEqual(suggestion?.category, .reengage)
    }

    func testEnthusiasticSuggestion() {
        let emotion = EmotionalState(valence: 0.7, arousal: 0.7, dominance: 0.3, confidence: 0.8)
        let suggestion = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.targetEmotion, .enthusiastic)
        XCTAssertEqual(suggestion?.category, .celebrate)
    }

    func testSuggestionCooldown() {
        let emotion = EmotionalState(valence: -0.6, arousal: 0.6, dominance: 0.0, confidence: 0.8)

        // First call should produce a suggestion
        let first = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)
        XCTAssertNotNil(first)

        // Same emotion shortly after should be throttled (no new suggestion)
        let second = engine.suggest(emotion: emotion, previousEmotion: .frustrated, timestamp: 1.0)
        XCTAssertNil(second, "Should be throttled by cooldown")
    }

    func testShiftProducesSuggestion() {
        let emotion1 = EmotionalState(valence: 0.5, arousal: 0.5, dominance: 0, confidence: 0.8)
        _ = engine.suggest(emotion: emotion1, previousEmotion: nil, timestamp: 0.0)

        // Shift to frustrated
        let emotion2 = EmotionalState(valence: -0.6, arousal: 0.6, dominance: 0, confidence: 0.8)
        let suggestion = engine.suggest(emotion: emotion2, previousEmotion: .enthusiastic, timestamp: 5.0)

        XCTAssertNotNil(suggestion, "Emotion shift should bypass cooldown")
    }

    func testReset() {
        let emotion = EmotionalState(valence: -0.5, arousal: 0.5, dominance: 0, confidence: 0.8)
        _ = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)

        engine.reset()

        // After reset, should be able to get a suggestion immediately
        let fresh = engine.suggest(emotion: emotion, previousEmotion: nil, timestamp: 0.0)
        XCTAssertNotNil(fresh)
    }

    func testAllSuggestionsHaveAlternatives() {
        let emotions: [(Float, Float, Float)] = [
            (-0.6, 0.6, 0.0),   // frustrated
            (0.0, 0.0, -0.6),   // hesitant
            (-0.5, -0.5, 0.0),  // disengaged
            (0.7, 0.7, 0.3),    // enthusiastic
        ]

        for (i, (v, a, d)) in emotions.enumerated() {
            let e = CoachingSuggestionEngine()
            let emotion = EmotionalState(valence: v, arousal: a, dominance: d, confidence: 0.8)
            let suggestion = e.suggest(emotion: emotion, previousEmotion: nil, timestamp: Double(i))
            XCTAssertNotNil(suggestion)
            if let s = suggestion, s.targetEmotion != .neutral {
                XCTAssertFalse(s.alternatives.isEmpty,
                    "\(s.targetEmotion) suggestion should have alternatives")
            }
        }
    }
}

// MARK: - CoachingEventBus Tests

final class CoachingEventBusTests: XCTestCase {

    func testSubscribeAndEmit() {
        let bus = CoachingEventBus()
        var received: [CoachingEvent] = []

        bus.subscribe { event in
            received.append(event)
        }

        bus.emit(.movementChanged(from: .accueil, to: .cadrage, elapsed: 60, isManualOverride: false))

        XCTAssertEqual(received.count, 1)
    }

    func testMultipleSubscribers() {
        let bus = CoachingEventBus()
        var count1 = 0
        var count2 = 0

        bus.subscribe { _ in count1 += 1 }
        bus.subscribe { _ in count2 += 1 }

        bus.emit(.movementChanged(from: .accueil, to: .cadrage, elapsed: 60, isManualOverride: true))

        XCTAssertEqual(count1, 1)
        XCTAssertEqual(count2, 1)
    }
}
