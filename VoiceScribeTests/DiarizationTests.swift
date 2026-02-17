import XCTest
@testable import VoiceScribe

// MARK: - SpeakerProfile Tests

final class SpeakerProfileTests: XCTestCase {

    func testCreation() {
        let speaker = SpeakerProfile(label: "Participant 1")
        XCTAssertEqual(speaker.label, "Participant 1")
        XCTAssertEqual(speaker.segmentCount, 0)
        XCTAssertEqual(speaker.totalSpeakingTime, 0)
        XCTAssertTrue(speaker.embedding.isEmpty)
    }

    func testRecordSegment() {
        var speaker = SpeakerProfile(label: "Test")
        speaker.recordSegment(duration: 5.0)
        XCTAssertEqual(speaker.segmentCount, 1)
        XCTAssertEqual(speaker.totalSpeakingTime, 5.0)
        speaker.recordSegment(duration: 3.0)
        XCTAssertEqual(speaker.segmentCount, 2)
        XCTAssertEqual(speaker.totalSpeakingTime, 8.0)
    }

    func testUniqueIds() {
        let a = SpeakerProfile(label: "A")
        let b = SpeakerProfile(label: "B")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testEquality() {
        let a = SpeakerProfile(label: "A", embedding: [1, 2, 3])
        var b = a
        b.label = "Modified"
        // Same UUID = equal (Hashable by id)
        XCTAssertEqual(a, b)
    }

    func testHashable() {
        let a = SpeakerProfile(label: "A")
        let b = SpeakerProfile(label: "B")
        let set: Set<SpeakerProfile> = [a, b, a]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Cosine Similarity

    func testCosineSimilarityIdentical() {
        let v: [Float] = [1.0, 2.0, 3.0]
        let sim = SpeakerProfile.cosineSimilarity(v, v)
        XCTAssertEqual(sim, 1.0, accuracy: 0.001)
    }

    func testCosineSimilarityOrthogonal() {
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [0.0, 1.0]
        let sim = SpeakerProfile.cosineSimilarity(a, b)
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    func testCosineSimilarityOpposite() {
        let a: [Float] = [1.0, 2.0]
        let b: [Float] = [-1.0, -2.0]
        let sim = SpeakerProfile.cosineSimilarity(a, b)
        XCTAssertEqual(sim, -1.0, accuracy: 0.001)
    }

    func testCosineSimilarityEmptyVectors() {
        let sim = SpeakerProfile.cosineSimilarity([], [])
        XCTAssertEqual(sim, 0.0)
    }

    func testCosineSimilarityMismatchedLengths() {
        let sim = SpeakerProfile.cosineSimilarity([1, 2], [1, 2, 3])
        XCTAssertEqual(sim, 0.0)
    }

    func testCosineSimilarityScaleInvariant() {
        let a: [Float] = [1.0, 2.0, 3.0]
        let b: [Float] = [2.0, 4.0, 6.0]
        let sim = SpeakerProfile.cosineSimilarity(a, b)
        XCTAssertEqual(sim, 1.0, accuracy: 0.001, "Cosine similarity should be scale-invariant")
    }
}

// MARK: - DiarizationSegment Tests

final class DiarizationSegmentTests: XCTestCase {

    func testDuration() {
        let speaker = SpeakerProfile(label: "Test")
        let seg = DiarizationSegment(speaker: speaker, startTime: 10.0, endTime: 15.5)
        XCTAssertEqual(seg.duration, 5.5, accuracy: 0.001)
    }

    func testDefaultConfidence() {
        let speaker = SpeakerProfile(label: "Test")
        let seg = DiarizationSegment(speaker: speaker, startTime: 0, endTime: 1)
        XCTAssertEqual(seg.confidence, 1.0)
    }

    func testUniqueIds() {
        let speaker = SpeakerProfile(label: "Test")
        let a = DiarizationSegment(speaker: speaker, startTime: 0, endTime: 1)
        let b = DiarizationSegment(speaker: speaker, startTime: 1, endTime: 2)
        XCTAssertNotEqual(a.id, b.id)
    }
}

// MARK: - DiarizationResult Tests

final class DiarizationResultTests: XCTestCase {

    func testEmpty() {
        let result = DiarizationResult.empty
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.speakerCount, 0)
    }

    func testWithSpeakers() {
        let s1 = SpeakerProfile(label: "A")
        let s2 = SpeakerProfile(label: "B")
        let seg = DiarizationSegment(speaker: s1, startTime: 0, endTime: 5)
        let result = DiarizationResult(segments: [seg], activeSpeakers: [s1, s2])
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.speakerCount, 2)
    }
}

// MARK: - SpeakerBalance Tests

final class SpeakerBalanceTests: XCTestCase {

    func testEmpty() {
        let balance = SpeakerBalance.empty
        XCTAssertNil(balance.dominantSpeaker)
        XCTAssertTrue(balance.isBalanced)
    }

    func testRatio() {
        let id1 = UUID()
        let id2 = UUID()
        let balance = SpeakerBalance(speakerTimes: [id1: 30, id2: 70], totalTime: 100)
        XCTAssertEqual(balance.ratio(for: id1), 0.3, accuracy: 0.001)
        XCTAssertEqual(balance.ratio(for: id2), 0.7, accuracy: 0.001)
    }

    func testDominantSpeaker() {
        let id1 = UUID()
        let id2 = UUID()
        let balance = SpeakerBalance(speakerTimes: [id1: 30, id2: 70], totalTime: 100)
        XCTAssertEqual(balance.dominantSpeaker, id2)
    }

    func testIsBalanced() {
        let id1 = UUID()
        let id2 = UUID()
        let balanced = SpeakerBalance(speakerTimes: [id1: 45, id2: 55], totalTime: 100)
        XCTAssertTrue(balanced.isBalanced)

        let unbalanced = SpeakerBalance(speakerTimes: [id1: 20, id2: 80], totalTime: 100)
        XCTAssertFalse(unbalanced.isBalanced)
    }

    func testRatioForUnknownSpeaker() {
        let balance = SpeakerBalance(speakerTimes: [UUID(): 50], totalTime: 100)
        XCTAssertEqual(balance.ratio(for: UUID()), 0.0)
    }
}

// MARK: - Mock Diarizer (for protocol contract tests)

final class MockDiarizer: DiarizationProvider {
    var onSpeakerChange: ((_ speaker: SpeakerProfile) -> Void)?

    private var speakers: [SpeakerProfile] = []
    private var processCallCount = 0

    func process(samples: [Float], timestamp: TimeInterval) {
        processCallCount += 1
    }

    func identifySpeaker(from samples: [Float]) -> SpeakerProfile? {
        speakers.first
    }

    func currentSpeakers() -> [SpeakerProfile] { speakers }

    func speakerBalance() -> SpeakerBalance { .empty }

    func reset() {
        speakers.removeAll()
        processCallCount = 0
    }

    func addSpeaker(_ speaker: SpeakerProfile) { speakers.append(speaker) }
}

final class DiarizationProviderContractTests: XCTestCase {

    func testResetClearsSpeakers() {
        let diarizer = MockDiarizer()
        diarizer.addSpeaker(SpeakerProfile(label: "A"))
        XCTAssertEqual(diarizer.currentSpeakers().count, 1)
        diarizer.reset()
        XCTAssertTrue(diarizer.currentSpeakers().isEmpty)
    }

    func testOnSpeakerChangeCallback() {
        let diarizer = MockDiarizer()
        var received: SpeakerProfile?
        diarizer.onSpeakerChange = { speaker in received = speaker }
        let speaker = SpeakerProfile(label: "Test")
        diarizer.onSpeakerChange?(speaker)
        XCTAssertEqual(received?.label, "Test")
    }

    func testIdentifySpeakerReturnsKnown() {
        let diarizer = MockDiarizer()
        let speaker = SpeakerProfile(label: "Marie")
        diarizer.addSpeaker(speaker)
        let identified = diarizer.identifySpeaker(from: [0.1, 0.2, 0.3])
        XCTAssertEqual(identified?.label, "Marie")
    }

    func testIdentifySpeakerReturnsNilWhenEmpty() {
        let diarizer = MockDiarizer()
        XCTAssertNil(diarizer.identifySpeaker(from: [0.1, 0.2]))
    }
}
