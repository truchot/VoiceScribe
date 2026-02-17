import Foundation

// MARK: - STT Backend (Value Object)

/// Supported speech-to-text backend types.
enum STTBackend: String, Codable, CaseIterable {
    case whisperLocal = "whisper-local"
    case voxtralWebSocket = "voxtral-ws"
    case whisperServer = "whisper-server"

    var displayName: String {
        switch self {
        case .whisperLocal: return "Whisper (local)"
        case .voxtralWebSocket: return "Voxtral (serveur)"
        case .whisperServer: return "Whisper (serveur)"
        }
    }

    var isLocal: Bool { self == .whisperLocal }
    var requiresServer: Bool { !isLocal }
}

// MARK: - STT Server Config (Value Object)

/// Configuration for a remote STT server endpoint.
/// Immutable value object with validation.
struct STTServerConfig: Codable, Equatable {
    let host: String
    let port: Int
    let language: String
    let model: String

    init(host: String = "localhost", port: Int = 8765, language: String = "auto", model: String = "voxtral") {
        self.host = host
        self.port = max(1, min(65535, port))
        self.language = language
        self.model = model
    }

    var webSocketURL: URL? {
        // Only allow wss:// in production; ws:// for localhost
        let scheme = (host == "localhost" || host == "127.0.0.1") ? "ws" : "wss"
        return URL(string: "\(scheme)://\(host):\(port)/transcribe")
    }

    static let `default` = STTServerConfig()
}

// MARK: - Partial Transcription (Value Object)

/// A streaming transcription result — may be partial (in-progress) or final.
struct PartialTranscription: Identifiable {
    let id: UUID
    let text: String
    let isFinal: Bool
    let confidence: Float
    let timestamp: TimeInterval
    let backend: STTBackend

    init(text: String, isFinal: Bool, confidence: Float = 1.0, timestamp: TimeInterval, backend: STTBackend) {
        self.id = UUID()
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = timestamp
        self.backend = backend
    }

    /// Convert a final partial result into a full TranscriptionSegment.
    func toSegment(speaker: Speaker, endTime: TimeInterval) -> TranscriptionSegment {
        TranscriptionSegment(
            text: text,
            startTime: timestamp,
            endTime: endTime,
            speaker: speaker,
            confidence: confidence
        )
    }
}

// MARK: - STT Connection State (Value Object)

/// Connection state for remote STT servers.
enum STTConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case error(String)

    var isConnected: Bool { self == .connected }
    var isUsable: Bool {
        switch self {
        case .connected, .reconnecting: return true
        default: return false
        }
    }

    var displayText: String {
        switch self {
        case .disconnected: return "Déconnecté"
        case .connecting: return "Connexion..."
        case .connected: return "Connecté"
        case .reconnecting(let n): return "Reconnexion (\(n))..."
        case .error(let msg): return "Erreur: \(msg)"
        }
    }

    var statusColor: String {
        switch self {
        case .connected: return "green"
        case .connecting, .reconnecting: return "orange"
        case .disconnected, .error: return "red"
        }
    }
}
