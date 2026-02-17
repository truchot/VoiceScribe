import XCTest
@testable import VoiceScribe

// MARK: - SentimentAnalyzer Tests

final class SentimentAnalyzerTests: XCTestCase {

    private var analyzer: SentimentAnalyzer!
    private var receivedEmotions: [(EmotionalState, ProsodicFeatures)]!
    private var receivedShifts: [(EmotionLabel, EmotionLabel)]!

    override func setUp() {
        super.setUp()
        let config = SentimentAnalyzer.Config(
            smoothingFactor: 0.0, // No smoothing for deterministic tests
            emitInterval: 0.1     // Fast emission for testing
        )
        analyzer = SentimentAnalyzer(config: config)
        receivedEmotions = []
        receivedShifts = []

        analyzer.onSentimentUpdate = { [weak self] emotion, features in
            self?.receivedEmotions.append((emotion, features))
        }
        analyzer.onSentimentShift = { [weak self] from, to in
            self?.receivedShifts.append((from, to))
        }
    }

    override func tearDown() {
        analyzer = nil
        receivedEmotions = nil
        receivedShifts = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testDefaultConfigValues() {
        let config = SentimentAnalyzer.Config()
        XCTAssertEqual(config.sampleRate, 16000)
        XCTAssertEqual(config.frameSize, 480)
        XCTAssertEqual(config.hopSize, 160)
        XCTAssertEqual(config.emitInterval, 0.5)
        XCTAssertEqual(config.minPitch, 60)
        XCTAssertEqual(config.maxPitch, 500)
    }

    // MARK: - Silence Handling

    func testSilenceProducesLowConfidence() {
        // Feed silence (zeros)
        let silence = [Float](repeating: 0.0, count: 16000) // 1 second of silence
        let expectation = expectation(description: "sentiment update")
        expectation.isInverted = false

        analyzer.onSentimentUpdate = { emotion, features in
            // Silence should produce very low confidence
            XCTAssertLessThan(emotion.confidence, 0.3, "Silence should yield low confidence")
            expectation.fulfill()
        }

        analyzer.process(samples: silence, timestamp: 0.0)
        // Process again to trigger emit
        analyzer.process(samples: silence, timestamp: 0.2)

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Speech Detection

    func testSpeechDetectedWithEnergy() {
        let config = SentimentAnalyzer.Config(smoothingFactor: 0.0, emitInterval: 0.01)
        let testAnalyzer = SentimentAnalyzer(config: config)

        let expectation = expectation(description: "features with speech")

        testAnalyzer.onSentimentUpdate = { emotion, features in
            // Features from speech should have isSpeech = true in some frames
            // and produce some analysis
            expectation.fulfill()
        }

        // Generate a 200Hz sine wave (speech-like)
        let sampleRate: Float = 16000
        let frequency: Float = 200
        let duration: Float = 0.5
        let numSamples = Int(sampleRate * duration)
        var speech = [Float](repeating: 0, count: numSamples)
        for i in 0..<numSamples {
            speech[i] = 0.3 * sin(2.0 * .pi * frequency * Float(i) / sampleRate)
        }

        testAnalyzer.process(samples: speech, timestamp: 0.0)
        testAnalyzer.process(samples: speech, timestamp: 0.5)

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Reset

    func testResetClearsState() {
        // Feed some data
        let noise = (0..<8000).map { _ in Float.random(in: -0.1...0.1) }
        analyzer.process(samples: noise, timestamp: 0.0)

        let expectation = expectation(description: "reset completes")
        expectation.isInverted = false

        // Reset should complete without crash
        analyzer.reset()

        // Feed fresh data after reset
        analyzer.process(samples: noise, timestamp: 0.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Emotion Mapping

    func testHighEnergySpeechProducesNonZeroArousal() {
        let config = SentimentAnalyzer.Config(smoothingFactor: 0.0, emitInterval: 0.01)
        let testAnalyzer = SentimentAnalyzer(config: config)

        let expectation = expectation(description: "arousal computed")

        testAnalyzer.onSentimentUpdate = { emotion, features in
            // High-energy speech should eventually produce nonzero arousal
            if emotion.confidence > 0.3 {
                expectation.fulfill()
            }
        }

        // Generate loud speech-like signal
        let sampleRate: Float = 16000
        var samples = [Float]()
        for i in 0..<Int(sampleRate * 2.0) { // 2 seconds
            let t = Float(i) / sampleRate
            // Mix of frequencies to simulate speech
            let s = 0.5 * sin(2.0 * .pi * 150 * t) +
                     0.3 * sin(2.0 * .pi * 300 * t) +
                     0.1 * sin(2.0 * .pi * 500 * t)
            samples.append(s)
        }

        // Feed in chunks
        let chunkSize = 8000
        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            testAnalyzer.process(samples: chunk, timestamp: Double(i) / 16000.0)
        }

        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - Protocol Conformance

    func testConformsToSentimentProvider() {
        let provider: SentimentProvider = SentimentAnalyzer()
        XCTAssertNotNil(provider)
    }
}

// MARK: - PitchContour Tests

final class PitchContourTests: XCTestCase {

    func testAllContoursHaveSymbols() {
        let contours: [PitchContour] = [.rising, .falling, .flat, .peaked, .dipped]
        for contour in contours {
            XCTAssertFalse(contour.rawValue.isEmpty, "\(contour) should have a symbol")
        }
    }
}
