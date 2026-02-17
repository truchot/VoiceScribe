import Foundation

/// WebSocket-based streaming speech-to-text client.
///
/// Supports multiple backends (Voxtral, remote Whisper server) via a common
/// JSON protocol. Audio is sent as binary frames, results arrive as JSON.
///
/// Thread safety: all mutable state is protected by `stateQueue` (serial).
/// Public methods may be called from any thread.
///
/// Protocol (server->client):
/// ```json
/// { "type": "partial", "text": "Bonj", "confidence": 0.7 }
/// { "type": "final",   "text": "Bonjour comment allez-vous", "confidence": 0.95 }
/// ```
final class WebSocketSTTClient: StreamingTranscriberProvider {

    // MARK: - Protocol Callbacks

    var onPartialResult: ((PartialTranscription) -> Void)?
    var onFinalResult: ((PartialTranscription) -> Void)?

    // MARK: - State (protected by stateQueue)

    private(set) var connectionState: STTConnectionState = .disconnected

    // MARK: - Private (all access serialized on stateQueue)

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var config: STTServerConfig?
    private var currentTimestamp: TimeInterval = 0
    private let reconnectMaxAttempts = 3
    private var reconnectAttempt = 0

    /// Serializes all mutable state access to prevent data races.
    private let stateQueue = DispatchQueue(label: "com.voicescribe.ws-stt.state", qos: .userInteractive)

    // MARK: - Connect

    func connect(config: STTServerConfig) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: STTClientError.connectionFailed("Client deallocated"))
                    return
                }

                self.config = config
                guard let url = config.webSocketURL else {
                    self.connectionState = .error("URL invalide")
                    continuation.resume(throwing: STTClientError.invalidURL)
                    return
                }

                self.connectionState = .connecting

                let urlSession = URLSession(configuration: .default)
                self.session = urlSession

                var request = URLRequest(url: url)
                request.timeoutInterval = 10

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

                self.connectionState = .connected
                self.reconnectAttempt = 0

                // Start receiving messages
                self.receiveMessages()

                continuation.resume()
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            self.connectionState = .disconnected
        }
    }

    // MARK: - Send Audio

    func sendAudio(samples: [Float], timestamp: TimeInterval) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.connectionState.isUsable, let task = self.webSocketTask else { return }
            self.currentTimestamp = timestamp

            // Convert Float32 samples to raw bytes (little-endian)
            let data = samples.withUnsafeBufferPointer { ptr in
                Data(buffer: ptr)
            }

            let message = URLSessionWebSocketTask.Message.data(data)
            task.send(message) { [weak self] error in
                if let error = error {
                    Log.audio.warning("WebSocket send error: \(error.localizedDescription)")
                    Task { @MainActor [weak self] in
                        self?.handleConnectionLoss()
                    }
                }
            }
        }
    }

    // MARK: - Receive Loop

    private func receiveMessages() {
        // Note: called from stateQueue — read webSocketTask safely
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.stateQueue.async { [weak self] in
                    self?.receiveMessages()
                }

            case .failure(let error):
                Log.audio.warning("WebSocket receive error: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    self?.handleConnectionLoss()
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

        // Read config safely
        let backend: STTBackend = stateQueue.sync {
            config?.model.contains("voxtral") == true ? .voxtralWebSocket : .whisperServer
        }
        let timestamp: TimeInterval = stateQueue.sync { currentTimestamp }

        let partial = PartialTranscription(
            text: text,
            isFinal: type == "final",
            confidence: confidence,
            timestamp: timestamp,
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
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.reconnectAttempt < self.reconnectMaxAttempts, let config = self.config else {
                self.connectionState = .error("Connexion perdue")
                return
            }

            self.reconnectAttempt += 1
            self.connectionState = .reconnecting(attempt: self.reconnectAttempt)

            let delay = Double(1 << self.reconnectAttempt) // 2s, 4s, 8s

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                do {
                    try await self?.connect(config: config)
                } catch {
                    Task { @MainActor [weak self] in
                        self?.handleConnectionLoss()
                    }
                }
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
