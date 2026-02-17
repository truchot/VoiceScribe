import Foundation

/// WebSocket-based streaming speech-to-text client.
///
/// Supports multiple backends (Voxtral, remote Whisper server) via a common
/// JSON protocol. Audio is sent as binary frames, results arrive as JSON.
///
/// Protocol (server→client):
/// ```json
/// { "type": "partial", "text": "Bonj", "confidence": 0.7 }
/// { "type": "final",   "text": "Bonjour comment allez-vous", "confidence": 0.95 }
/// ```
final class WebSocketSTTClient: StreamingTranscriberProvider {

    // MARK: - Protocol Callbacks

    var onPartialResult: ((PartialTranscription) -> Void)?
    var onFinalResult: ((PartialTranscription) -> Void)?

    // MARK: - State

    private(set) var connectionState: STTConnectionState = .disconnected

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var config: STTServerConfig?
    private var currentTimestamp: TimeInterval = 0
    private let reconnectMaxAttempts = 3
    private var reconnectAttempt = 0

    private let sendQueue = DispatchQueue(label: "com.voicescribe.ws-stt", qos: .userInteractive)

    // MARK: - Connect

    func connect(config: STTServerConfig) async throws {
        self.config = config
        guard let url = config.webSocketURL else {
            connectionState = .error("URL invalide")
            throw STTClientError.invalidURL
        }

        connectionState = .connecting

        let urlSession = URLSession(configuration: .default)
        self.session = urlSession

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        // Send language/model config as query params or headers
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = [
                URLQueryItem(name: "language", value: config.language),
                URLQueryItem(name: "model", value: config.model)
            ]
            if let configuredURL = components.url {
                request.url = configuredURL
            }
        }

        let task = urlSession.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        connectionState = .connected
        reconnectAttempt = 0

        // Start receiving messages
        receiveMessages()
    }

    // MARK: - Disconnect

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        connectionState = .disconnected
    }

    // MARK: - Send Audio

    func sendAudio(samples: [Float], timestamp: TimeInterval) {
        guard connectionState.isUsable, let task = webSocketTask else { return }
        currentTimestamp = timestamp

        sendQueue.async {
            // Convert Float32 samples to raw bytes (little-endian)
            let data = samples.withUnsafeBufferPointer { ptr in
                Data(buffer: ptr)
            }

            let message = URLSessionWebSocketTask.Message.data(data)
            task.send(message) { [weak self] error in
                if let error = error {
                    Log.audio.warning("WebSocket send error: \(error.localizedDescription)")
                    Task { @MainActor in
                        self?.handleConnectionLoss()
                    }
                }
            }
        }
    }

    // MARK: - Receive Loop

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.receiveMessages()

            case .failure(let error):
                Log.audio.warning("WebSocket receive error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.handleConnectionLoss()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            guard let d = text.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let text = json["text"] as? String else { return }

        let confidence = (json["confidence"] as? Double).map(Float.init) ?? 1.0
        let backend: STTBackend = config?.model.contains("voxtral") == true ? .voxtralWebSocket : .whisperServer

        let partial = PartialTranscription(
            text: text,
            isFinal: type == "final",
            confidence: confidence,
            timestamp: currentTimestamp,
            backend: backend
        )

        if type == "final" {
            onFinalResult?(partial)
        } else {
            onPartialResult?(partial)
        }
    }

    // MARK: - Reconnection

    private func handleConnectionLoss() {
        guard reconnectAttempt < reconnectMaxAttempts, let config = config else {
            connectionState = .error("Connexion perdue")
            return
        }

        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)

        let delay = Double(1 << reconnectAttempt) // 2s, 4s, 8s

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            do {
                try await connect(config: config)
            } catch {
                handleConnectionLoss()
            }
        }
    }

    // MARK: - Error

    enum STTClientError: LocalizedError {
        case invalidURL
        case connectionFailed(String)
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL du serveur STT invalide"
            case .connectionFailed(let msg): return "Connexion échouée: \(msg)"
            case .serverError(let msg): return "Erreur serveur: \(msg)"
            }
        }
    }
}
