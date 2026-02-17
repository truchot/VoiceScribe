import XCTest
@testable import VoiceScribe

// MARK: - STTBackend Tests

final class STTBackendTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(STTBackend.allCases.count, 3)
    }

    func testIsLocal() {
        XCTAssertTrue(STTBackend.whisperLocal.isLocal)
        XCTAssertFalse(STTBackend.voxtralWebSocket.isLocal)
        XCTAssertFalse(STTBackend.whisperServer.isLocal)
    }

    func testRequiresServer() {
        XCTAssertFalse(STTBackend.whisperLocal.requiresServer)
        XCTAssertTrue(STTBackend.voxtralWebSocket.requiresServer)
        XCTAssertTrue(STTBackend.whisperServer.requiresServer)
    }

    func testDisplayNames() {
        for backend in STTBackend.allCases {
            XCTAssertFalse(backend.displayName.isEmpty, "\(backend) should have a display name")
        }
    }

    func testRawValues() {
        XCTAssertEqual(STTBackend.whisperLocal.rawValue, "whisper-local")
        XCTAssertEqual(STTBackend.voxtralWebSocket.rawValue, "voxtral-ws")
        XCTAssertEqual(STTBackend.whisperServer.rawValue, "whisper-server")
    }
}

// MARK: - STTServerConfig Tests

final class STTServerConfigTests: XCTestCase {

    func testDefaults() {
        let config = STTServerConfig.default
        XCTAssertEqual(config.host, "localhost")
        XCTAssertEqual(config.port, 8765)
        XCTAssertEqual(config.language, "auto")
        XCTAssertEqual(config.model, "voxtral")
    }

    func testWebSocketURL() {
        let config = STTServerConfig(host: "192.168.1.10", port: 9090)
        XCTAssertEqual(config.webSocketURL?.absoluteString, "ws://192.168.1.10:9090/transcribe")
    }

    func testDefaultWebSocketURL() {
        let config = STTServerConfig.default
        XCTAssertEqual(config.webSocketURL?.absoluteString, "ws://localhost:8765/transcribe")
    }

    func testEquality() {
        let a = STTServerConfig(host: "localhost", port: 8765)
        let b = STTServerConfig(host: "localhost", port: 8765)
        XCTAssertEqual(a, b)

        let c = STTServerConfig(host: "remote", port: 8765)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - PartialTranscription Tests

final class PartialTranscriptionTests: XCTestCase {

    func testCreation() {
        let partial = PartialTranscription(
            text: "Bonjour",
            isFinal: false,
            confidence: 0.8,
            timestamp: 10.0,
            backend: .voxtralWebSocket
        )
        XCTAssertEqual(partial.text, "Bonjour")
        XCTAssertFalse(partial.isFinal)
        XCTAssertEqual(partial.confidence, 0.8)
        XCTAssertEqual(partial.timestamp, 10.0)
        XCTAssertEqual(partial.backend, .voxtralWebSocket)
    }

    func testUniqueIds() {
        let a = PartialTranscription(text: "a", isFinal: false, timestamp: 0, backend: .whisperLocal)
        let b = PartialTranscription(text: "b", isFinal: false, timestamp: 0, backend: .whisperLocal)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testToSegment() {
        let partial = PartialTranscription(
            text: "Bonjour le monde",
            isFinal: true,
            confidence: 0.95,
            timestamp: 5.0,
            backend: .whisperLocal
        )
        let segment = partial.toSegment(speaker: .other, endTime: 8.0)
        XCTAssertEqual(segment.text, "Bonjour le monde")
        XCTAssertEqual(segment.startTime, 5.0)
        XCTAssertEqual(segment.endTime, 8.0)
        XCTAssertEqual(segment.speaker, .other)
        XCTAssertEqual(segment.confidence, 0.95)
    }

    func testDefaultConfidence() {
        let partial = PartialTranscription(text: "test", isFinal: true, timestamp: 0, backend: .whisperLocal)
        XCTAssertEqual(partial.confidence, 1.0)
    }
}

// MARK: - STTConnectionState Tests

final class STTConnectionStateTests: XCTestCase {

    func testIsConnected() {
        XCTAssertTrue(STTConnectionState.connected.isConnected)
        XCTAssertFalse(STTConnectionState.disconnected.isConnected)
        XCTAssertFalse(STTConnectionState.connecting.isConnected)
        XCTAssertFalse(STTConnectionState.error("fail").isConnected)
    }

    func testIsUsable() {
        XCTAssertTrue(STTConnectionState.connected.isUsable)
        XCTAssertTrue(STTConnectionState.reconnecting(attempt: 1).isUsable)
        XCTAssertFalse(STTConnectionState.disconnected.isUsable)
        XCTAssertFalse(STTConnectionState.error("x").isUsable)
    }

    func testDisplayText() {
        XCTAssertEqual(STTConnectionState.connected.displayText, "Connecté")
        XCTAssertEqual(STTConnectionState.disconnected.displayText, "Déconnecté")
        XCTAssertTrue(STTConnectionState.error("timeout").displayText.contains("timeout"))
    }

    func testStatusColor() {
        XCTAssertEqual(STTConnectionState.connected.statusColor, "green")
        XCTAssertEqual(STTConnectionState.connecting.statusColor, "orange")
        XCTAssertEqual(STTConnectionState.disconnected.statusColor, "red")
    }

    func testEquality() {
        XCTAssertEqual(STTConnectionState.connected, STTConnectionState.connected)
        XCTAssertNotEqual(STTConnectionState.connected, STTConnectionState.disconnected)
        XCTAssertEqual(STTConnectionState.error("a"), STTConnectionState.error("a"))
        XCTAssertNotEqual(STTConnectionState.error("a"), STTConnectionState.error("b"))
    }
}

// MARK: - Mock Streaming Transcriber (for protocol contract tests)

final class MockStreamingTranscriber: StreamingTranscriberProvider {
    var onPartialResult: ((PartialTranscription) -> Void)?
    var onFinalResult: ((PartialTranscription) -> Void)?
    private(set) var connectionState: STTConnectionState = .disconnected

    private var sentSamples: [[Float]] = []

    func connect(config: STTServerConfig) async throws {
        connectionState = .connected
    }

    func disconnect() {
        connectionState = .disconnected
    }

    func sendAudio(samples: [Float], timestamp: TimeInterval) {
        sentSamples.append(samples)
    }

    var sentSampleCount: Int { sentSamples.count }
}

final class StreamingTranscriberContractTests: XCTestCase {

    func testConnectDisconnect() async throws {
        let client = MockStreamingTranscriber()
        XCTAssertEqual(client.connectionState, .disconnected)
        try await client.connect(config: .default)
        XCTAssertEqual(client.connectionState, .connected)
        client.disconnect()
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func testSendAudioAccumulates() async throws {
        let client = MockStreamingTranscriber()
        try await client.connect(config: .default)
        client.sendAudio(samples: [0.1, 0.2], timestamp: 0)
        client.sendAudio(samples: [0.3, 0.4], timestamp: 1)
        XCTAssertEqual(client.sentSampleCount, 2)
    }

    func testPartialResultCallback() async throws {
        let client = MockStreamingTranscriber()
        var received: PartialTranscription?
        client.onPartialResult = { received = $0 }
        let partial = PartialTranscription(text: "Bonjour", isFinal: false, timestamp: 0, backend: .voxtralWebSocket)
        client.onPartialResult?(partial)
        XCTAssertEqual(received?.text, "Bonjour")
        XCTAssertFalse(received?.isFinal ?? true)
    }

    func testFinalResultCallback() async throws {
        let client = MockStreamingTranscriber()
        var received: PartialTranscription?
        client.onFinalResult = { received = $0 }
        let final_ = PartialTranscription(text: "Bonjour le monde", isFinal: true, timestamp: 0, backend: .voxtralWebSocket)
        client.onFinalResult?(final_)
        XCTAssertEqual(received?.text, "Bonjour le monde")
        XCTAssertTrue(received?.isFinal ?? false)
    }
}
