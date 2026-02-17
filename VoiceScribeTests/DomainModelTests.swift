import XCTest
@testable import VoiceScribe

// MARK: - EmotionalState Tests

final class EmotionalStateTests: XCTestCase {

    // MARK: - Label Classification

    func testNeutralWhenConfidenceBelowThreshold() {
        let state = EmotionalState(valence: 0.8, arousal: 0.8, dominance: 0.5, confidence: 0.1)
        XCTAssertEqual(state.label, .neutral, "Low confidence should always yield .neutral")
    }

    func testEnthusiasticLabel() {
        let state = EmotionalState(valence: 0.5, arousal: 0.5, dominance: 0.0, confidence: 0.8)
        XCTAssertEqual(state.label, .enthusiastic, "High valence + high arousal = enthusiastic")
    }

    func testSatisfiedLabel() {
        let state = EmotionalState(valence: 0.5, arousal: -0.5, dominance: 0.0, confidence: 0.8)
        XCTAssertEqual(state.label, .satisfied, "High valence + low arousal = satisfied")
    }

    func testFrustratedLabel() {
        let state = EmotionalState(valence: -0.5, arousal: 0.5, dominance: 0.0, confidence: 0.8)
        XCTAssertEqual(state.label, .frustrated, "Low valence + high arousal = frustrated")
    }

    func testDisengagedLabel() {
        let state = EmotionalState(valence: -0.5, arousal: -0.5, dominance: 0.0, confidence: 0.8)
        XCTAssertEqual(state.label, .disengaged, "Low valence + low arousal = disengaged")
    }

    func testHesitantLabel() {
        let state = EmotionalState(valence: 0.0, arousal: 0.0, dominance: -0.5, confidence: 0.8)
        XCTAssertEqual(state.label, .hesitant, "Low dominance = hesitant")
    }

    func testConfidentLabel() {
        let state = EmotionalState(valence: 0.2, arousal: 0.0, dominance: 0.5, confidence: 0.8)
        XCTAssertEqual(state.label, .confident, "High dominance + positive valence = confident")
    }

    func testAnimatedLabel() {
        let state = EmotionalState(valence: 0.0, arousal: 0.6, dominance: 0.0, confidence: 0.8)
        XCTAssertEqual(state.label, .animated, "Very high arousal alone = animated")
    }

    func testDefaultStateIsNeutral() {
        let state = EmotionalState()
        XCTAssertEqual(state.label, .neutral)
        XCTAssertEqual(state.valence, 0.0)
        XCTAssertEqual(state.arousal, 0.0)
        XCTAssertEqual(state.dominance, 0.0)
        XCTAssertEqual(state.confidence, 0.0)
    }
}

// MARK: - EmotionLabel Tests

final class EmotionLabelTests: XCTestCase {

    func testCommercialSignalPositive() {
        let positive: [EmotionLabel] = [.enthusiastic, .satisfied, .confident]
        for label in positive {
            XCTAssertEqual(label.commercialSignal, .positive, "\(label) should be positive")
        }
    }

    func testCommercialSignalNeutral() {
        let neutral: [EmotionLabel] = [.animated, .neutral]
        for label in neutral {
            XCTAssertEqual(label.commercialSignal, .neutral, "\(label) should be neutral")
        }
    }

    func testCommercialSignalNegative() {
        let negative: [EmotionLabel] = [.hesitant, .frustrated, .disengaged]
        for label in negative {
            XCTAssertEqual(label.commercialSignal, .negative, "\(label) should be negative")
        }
    }

    func testAllCasesHaveEmoji() {
        for label in EmotionLabel.allCases {
            XCTAssertFalse(label.emoji.isEmpty, "\(label) should have an emoji")
        }
    }

    func testAllCasesHaveRawValue() {
        for label in EmotionLabel.allCases {
            XCTAssertFalse(label.rawValue.isEmpty, "\(label) should have a French raw value")
        }
    }
}

// MARK: - TranscriptionSegment Tests

final class TranscriptionSegmentTests: XCTestCase {

    func testFormattedTime() {
        let seg = TranscriptionSegment(text: "test", startTime: 125.5, endTime: 130.0)
        XCTAssertEqual(seg.formattedTime, "02:05")
    }

    func testFormattedTimeZero() {
        let seg = TranscriptionSegment(text: "test", startTime: 0, endTime: 1.0)
        XCTAssertEqual(seg.formattedTime, "00:00")
    }

    func testFormattedTimeOneHour() {
        let seg = TranscriptionSegment(text: "test", startTime: 3661, endTime: 3662)
        XCTAssertEqual(seg.formattedTime, "61:01")
    }

    func testSentimentEmoji() {
        let emotion = EmotionalState(valence: 0.5, arousal: 0.5, dominance: 0, confidence: 0.8)
        let seg = TranscriptionSegment(text: "test", startTime: 0, endTime: 1, sentiment: emotion)
        XCTAssertFalse(seg.sentimentEmoji.isEmpty)
    }

    func testSentimentEmojiNilSentiment() {
        let seg = TranscriptionSegment(text: "test", startTime: 0, endTime: 1)
        XCTAssertEqual(seg.sentimentEmoji, "")
    }

    func testDefaultSpeakerIsUnknown() {
        let seg = TranscriptionSegment(text: "test", startTime: 0, endTime: 1)
        XCTAssertEqual(seg.speaker, .unknown)
    }

    func testUniqueIds() {
        let seg1 = TranscriptionSegment(text: "a", startTime: 0, endTime: 1)
        let seg2 = TranscriptionSegment(text: "b", startTime: 0, endTime: 1)
        XCTAssertNotEqual(seg1.id, seg2.id)
    }
}

// MARK: - TranscriptionSession Tests

final class TranscriptionSessionTests: XCTestCase {

    func testNewSessionHasNoSegments() {
        let session = TranscriptionSession(title: "Test")
        XCTAssertEqual(session.segmentCount, 0)
        XCTAssertFalse(session.isFinished)
    }

    func testAddSegment() {
        var session = TranscriptionSession(title: "Test")
        let seg = TranscriptionSegment(text: "Bonjour", startTime: 0, endTime: 1, speaker: .me)
        let accepted = session.addSegment(seg)
        XCTAssertTrue(accepted)
        XCTAssertEqual(session.segmentCount, 1)
    }

    func testDeduplicationRejectsSimilar() {
        var session = TranscriptionSession(title: "Test")
        let seg1 = TranscriptionSegment(text: "Bonjour comment allez-vous", startTime: 0, endTime: 1, speaker: .me)
        let seg2 = TranscriptionSegment(text: "Bonjour comment allez-vous", startTime: 1, endTime: 2, speaker: .me)
        session.addSegment(seg1)
        let accepted = session.addSegment(seg2)
        XCTAssertFalse(accepted, "Identical text from same speaker should be rejected")
        XCTAssertEqual(session.segmentCount, 1)
    }

    func testDeduplicationAllowsDifferentSpeakers() {
        var session = TranscriptionSession(title: "Test")
        let seg1 = TranscriptionSegment(text: "Bonjour", startTime: 0, endTime: 1, speaker: .me)
        let seg2 = TranscriptionSegment(text: "Bonjour", startTime: 1, endTime: 2, speaker: .other)
        session.addSegment(seg1)
        let accepted = session.addSegment(seg2)
        XCTAssertTrue(accepted, "Same text from different speakers should be accepted")
        XCTAssertEqual(session.segmentCount, 2)
    }

    func testFinishSession() {
        var session = TranscriptionSession(title: "Test")
        XCTAssertFalse(session.isFinished)
        session.finish()
        XCTAssertTrue(session.isFinished)
        XCTAssertNotNil(session.endDate)
    }

    func testFinishIsIdempotent() {
        var session = TranscriptionSession(title: "Test")
        session.finish()
        let firstEnd = session.endDate
        session.finish()
        XCTAssertEqual(session.endDate, firstEnd)
    }

    func testRename() {
        var session = TranscriptionSession(title: "Old")
        session.rename("New")
        XCTAssertEqual(session.title, "New")
    }

    func testFullText() {
        var session = TranscriptionSession(title: "Test")
        session.addSegment(TranscriptionSegment(text: "Hello", startTime: 0, endTime: 1))
        session.addSegment(TranscriptionSegment(text: "World", startTime: 1, endTime: 2, speaker: .other))
        XCTAssertEqual(session.fullText, "Hello World")
    }

    func testRecentSegments() {
        var session = TranscriptionSession(title: "Test")
        for i in 0..<30 {
            session.addSegment(TranscriptionSegment(
                text: "Segment \(i)", startTime: Double(i), endTime: Double(i+1), speaker: .me
            ))
        }
        let recent = session.recentSegments(5)
        XCTAssertEqual(recent.count, 5)
        XCTAssertEqual(recent.first?.text, "Segment 25")
    }

    func testExportMarkdown() {
        var session = TranscriptionSession(title: "Demo")
        session.addSegment(TranscriptionSegment(text: "Bonjour", startTime: 0, endTime: 1, speaker: .me))
        let md = session.exportMarkdown()
        XCTAssertTrue(md.contains("# Demo"))
        XCTAssertTrue(md.contains("Bonjour"))
        XCTAssertTrue(md.contains("Moi"))
    }

    func testExportSRT() {
        var session = TranscriptionSession(title: "Demo")
        session.addSegment(TranscriptionSegment(text: "Bonjour", startTime: 0, endTime: 1.5, speaker: .me))
        let srt = session.exportSRT()
        XCTAssertTrue(srt.contains("1\n"))
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:01,500"))
        XCTAssertTrue(srt.contains("Bonjour"))
    }

    func testSentimentSummaryEmpty() {
        let session = TranscriptionSession(title: "Test")
        let summary = session.sentimentSummary()
        XCTAssertEqual(summary.dominantEmotion, .neutral)
    }

    func testSentimentSummaryWithData() {
        var session = TranscriptionSession(title: "Test")
        let happyEmotion = EmotionalState(valence: 0.6, arousal: 0.6, dominance: 0.2, confidence: 0.8)
        for i in 0..<10 {
            session.addSegment(TranscriptionSegment(
                text: "Good \(i)", startTime: Double(i), endTime: Double(i+1),
                speaker: .other, sentiment: happyEmotion
            ))
        }
        let summary = session.sentimentSummary()
        XCTAssertEqual(summary.dominantEmotion, .enthusiastic)
        XCTAssertGreaterThan(summary.averageValence, 0.0)
    }
}

// MARK: - Speaker Tests

final class SpeakerTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(Speaker.me.rawValue, "Moi")
        XCTAssertEqual(Speaker.other.rawValue, "Participant")
        XCTAssertEqual(Speaker.unknown.rawValue, "...")
    }

    func testAllCases() {
        XCTAssertEqual(Speaker.allCases.count, 3)
    }
}

// MARK: - ConversationMovement Tests

final class ConversationMovementTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(ConversationMovement.allCases.count, 11)
    }

    func testNextMovement() {
        XCTAssertEqual(ConversationMovement.accueil.next, .cadrage)
        XCTAssertEqual(ConversationMovement.engagement.next, .suivi)
        XCTAssertNil(ConversationMovement.suivi.next)
    }

    func testPreviousMovement() {
        XCTAssertNil(ConversationMovement.accueil.previous)
        XCTAssertEqual(ConversationMovement.cadrage.previous, .accueil)
        XCTAssertEqual(ConversationMovement.suivi.previous, .engagement)
    }

    func testExpectedDurationOrder() {
        for movement in ConversationMovement.allCases {
            let (min, max) = movement.expectedDuration
            XCTAssertLessThanOrEqual(min, max, "\(movement.name) min should be <= max")
            XCTAssertGreaterThan(min, 0, "\(movement.name) min should be > 0")
        }
    }

    func testIdealRatioRange() {
        for movement in ConversationMovement.allCases {
            let ratio = movement.idealMyRatio
            XCTAssertGreaterThanOrEqual(ratio, 0.0, "\(movement.name) ratio should be >= 0")
            XCTAssertLessThanOrEqual(ratio, 1.0, "\(movement.name) ratio should be <= 1")
        }
    }

    func testActMapping() {
        // connexion: accueil, cadrage, univers
        XCTAssertEqual(ConversationMovement.accueil.act, .connexion)
        XCTAssertEqual(ConversationMovement.cadrage.act, .connexion)
        XCTAssertEqual(ConversationMovement.univers.act, .connexion)
        // exploration: enjeux, profondeur, vision, qualification
        XCTAssertEqual(ConversationMovement.enjeux.act, .exploration)
        XCTAssertEqual(ConversationMovement.profondeur.act, .exploration)
        XCTAssertEqual(ConversationMovement.vision.act, .exploration)
        XCTAssertEqual(ConversationMovement.qualification.act, .exploration)
        // solution: proposition, dialogue, engagement
        XCTAssertEqual(ConversationMovement.proposition.act, .solution)
        XCTAssertEqual(ConversationMovement.dialogue.act, .solution)
        XCTAssertEqual(ConversationMovement.engagement.act, .solution)
        // suivi
        XCTAssertEqual(ConversationMovement.suivi.act, .suivi)
    }

    func testAllMovementsHaveNames() {
        for movement in ConversationMovement.allCases {
            XCTAssertFalse(movement.name.isEmpty)
            XCTAssertFalse(movement.emoji.isEmpty)
            XCTAssertFalse(movement.shortLabel.isEmpty)
        }
    }
}

// MARK: - RunningStats Tests

final class RunningStatsTests: XCTestCase {

    func testEmptyStats() {
        let stats = RunningStats(windowSize: 10)
        XCTAssertEqual(stats.count, 0)
        XCTAssertEqual(stats.mean, 0)
        XCTAssertEqual(stats.stdDev, 0)
    }

    func testSingleValue() {
        var stats = RunningStats(windowSize: 10)
        stats.add(5.0)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.mean, 5.0)
        XCTAssertEqual(stats.variance, 0) // n=1, variance=0
    }

    func testMeanComputation() {
        var stats = RunningStats(windowSize: 10)
        stats.add(2.0)
        stats.add(4.0)
        stats.add(6.0)
        XCTAssertEqual(stats.mean, 4.0, accuracy: 0.001)
    }

    func testWindowSliding() {
        var stats = RunningStats(windowSize: 3)
        stats.add(10.0)
        stats.add(10.0)
        stats.add(10.0)
        XCTAssertEqual(stats.mean, 10.0, accuracy: 0.001)
        // Now push out old values
        stats.add(20.0)
        XCTAssertEqual(stats.count, 3)
        // Window is now [10, 10, 20]
        XCTAssertEqual(stats.mean, 40.0 / 3.0, accuracy: 0.001)
    }

    func testStandardDeviation() {
        var stats = RunningStats(windowSize: 100)
        // Values: 2, 4, 4, 4, 5, 5, 7, 9
        for v: Float in [2, 4, 4, 4, 5, 5, 7, 9] {
            stats.add(v)
        }
        // Mean = 5.0, sample variance = 4.571, stdDev ≈ 2.138
        XCTAssertEqual(stats.mean, 5.0, accuracy: 0.001)
        XCTAssertEqual(stats.stdDev, 2.138, accuracy: 0.01)
    }
}

// MARK: - Float Array Extensions

final class FloatArrayExtensionTests: XCTestCase {

    func testStandardDeviationEmpty() {
        let arr: [Float] = []
        XCTAssertEqual(arr.standardDeviation(), 0)
    }

    func testStandardDeviationSingleValue() {
        let arr: [Float] = [5.0]
        XCTAssertEqual(arr.standardDeviation(), 0)
    }

    func testStandardDeviationValues() {
        let arr: [Float] = [2, 4, 4, 4, 5, 5, 7, 9]
        XCTAssertEqual(arr.standardDeviation(), 2.138, accuracy: 0.01)
    }
}

// MARK: - AudioFrameBuffer Tests

final class AudioFrameBufferTests: XCTestCase {

    func testEmptyBuffer() {
        let buf = AudioFrameBuffer(capacity: 1024)
        XCTAssertTrue(buf.isEmpty)
        XCTAssertEqual(buf.count, 0)
    }

    func testAppendAndCount() {
        var buf = AudioFrameBuffer(capacity: 1024)
        buf.append([1.0, 2.0, 3.0])
        XCTAssertEqual(buf.count, 3)
        XCTAssertFalse(buf.isEmpty)
    }

    func testConsumeFrameCopy() {
        var buf = AudioFrameBuffer(capacity: 1024)
        buf.append([1.0, 2.0, 3.0, 4.0, 5.0])
        let frame = buf.consumeFrameCopy(count: 3)
        XCTAssertEqual(frame, [1.0, 2.0, 3.0])
        XCTAssertEqual(buf.count, 2)
    }

    func testOverlappingConsume() {
        var buf = AudioFrameBuffer(capacity: 1024)
        buf.append([1.0, 2.0, 3.0, 4.0, 5.0])
        let frame = buf.consumeFrameCopy(count: 4, advance: 2)
        XCTAssertEqual(frame, [1.0, 2.0, 3.0, 4.0])
        XCTAssertEqual(buf.count, 3) // 5 - 2 = 3
    }

    func testRemoveAll() {
        var buf = AudioFrameBuffer(capacity: 1024)
        buf.append([1.0, 2.0, 3.0])
        buf.removeAll()
        XCTAssertTrue(buf.isEmpty)
        XCTAssertEqual(buf.count, 0)
    }

    func testCompaction() {
        var buf = AudioFrameBuffer(capacity: 8)
        buf.append([1.0, 2.0, 3.0, 4.0])
        _ = buf.consumeFrameCopy(count: 3)
        // readIndex=3, writeIndex=4, count=1
        // Append more — should trigger compaction
        buf.append([5.0, 6.0, 7.0, 8.0, 9.0])
        XCTAssertEqual(buf.count, 6)
    }
}

// MARK: - CoachingThresholds Tests

final class CoachingThresholdsTests: XCTestCase {

    func testThresholdsArePositive() {
        XCTAssertGreaterThan(CoachingThresholds.movementSwitchConfidence, 0)
        XCTAssertGreaterThan(CoachingThresholds.movementSwitchMinScore, 0)
        XCTAssertGreaterThan(CoachingThresholds.emotionMinConfidence, 0)
        XCTAssertGreaterThan(CoachingThresholds.suggestionCooldown, 0)
        XCTAssertGreaterThan(CoachingThresholds.dedupSimilarityThreshold, 0)
    }

    func testEmotionThresholdConsistency() {
        // Ensure thresholds are within valid ranges
        XCTAssertLessThanOrEqual(CoachingThresholds.emotionValenceThreshold, 1.0)
        XCTAssertLessThanOrEqual(CoachingThresholds.emotionArousalThreshold, 1.0)
        XCTAssertLessThanOrEqual(CoachingThresholds.emotionDominanceThreshold, 1.0)
        XCTAssertLessThanOrEqual(CoachingThresholds.emotionAnimatedArousal, 1.0)
    }
}
