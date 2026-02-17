import Foundation
import SwiftUI

/// Composition Root: owns all stores and wires the coordinator with
/// concrete infrastructure implementations.
///
/// Injected at the app root via `.environmentObject()`.
/// Individual views pick only the store(s) they need, so a change
/// in sentiment data doesn't re-render the transcription list,
/// and a new segment doesn't re-render the coaching panel.
///
/// Architecture:
/// ```
/// AppEnvironment (composition root)
///   ├─ RecordingStore     @Published: state, modelLoaded, error, elapsed
///   ├─ AudioStore         @Published: micLevel, sysLevel, captureSystemAudio
///   ├─ TranscriptionStore @Published: session, liveText, savedCount
///   ├─ SentimentStore     @Published: emotion, features, timeline
///   ├─ CoachingStore      @Published: output, movement, enabled
///   └─ RecordingCoordinator (non-observable pipeline brain)
/// ```
@MainActor
final class AppEnvironment: ObservableObject {
    
    // MARK: - Stores
    
    let recording: RecordingStore
    let audio: AudioStore
    let transcription: TranscriptionStore
    let sentiment: SentimentStore
    let coaching: CoachingStore
    let overlay: OverlayManager
    
    // MARK: - Coordinator
    
    private(set) var coordinator: RecordingCoordinator!
    
    // MARK: - Production Init (Composition Root)
    
    init() {
        self.recording = RecordingStore()
        self.audio = AudioStore()
        self.transcription = TranscriptionStore()
        self.sentiment = SentimentStore()
        self.coaching = CoachingStore()
        self.overlay = OverlayManager()
        
        // Composition root: all concrete types instantiated HERE, not in Coordinator
        coordinator = RecordingCoordinator(
            recording: recording,
            audio: audio,
            transcription: transcription,
            sentiment: sentiment,
            coaching: coaching,
            micVAD: SileroVAD(),
            systemVAD: SileroVAD(),
            sentimentProvider: SentimentAnalyzer(),
            coachEngine: ConversationCoach(),
            hybridSentiment: HybridSentiment(),
            diarizer: SpeakerDiarizer(),
            streamingSTT: WebSocketSTTClient(),
            semanticSentiment: SemanticSentimentAnalyzer(),
            makeVAD: { threshold in SileroVAD(config: .init(speechThreshold: threshold)) },
            makeSentiment: { smoothing in SentimentAnalyzer(config: .init(smoothingFactor: smoothing)) },
            makeTranscriber: { path, lang in WhisperTranscriber(config: .init(modelPath: path, language: lang)) }
        )
        
        // Wire overlay
        overlay.configure(
            env: self,
            recording: recording,
            audio: audio,
            transcription: transcription,
            sentiment: sentiment,
            coaching: coaching
        )
        
        // Wire overlay hotkey
        coordinator.hotkeys.onToggleOverlay = { [weak self] in
            Task { @MainActor in self?.overlay.toggle() }
        }
    }
    
    /// Test-friendly init: inject mock components
    init(
        micVAD: VADProvider,
        systemVAD: VADProvider,
        sentimentProvider: SentimentProvider,
        coachEngine: CoachingProvider,
        hybridSentiment: HybridSentimentProvider,
        persistence: PersistenceProvider,
        makeVAD: @escaping (Float) -> VADProvider = { _ in SileroVAD() },
        makeSentiment: @escaping (Float) -> SentimentProvider = { _ in SentimentAnalyzer() },
        makeTranscriber: @escaping (String, String) -> TranscriberProvider = { p, l in WhisperTranscriber(config: .init(modelPath: p, language: l)) }
    ) {
        self.recording = RecordingStore()
        self.audio = AudioStore()
        self.transcription = TranscriptionStore(persistence: persistence)
        self.sentiment = SentimentStore()
        self.coaching = CoachingStore()
        self.overlay = OverlayManager()
        
        self.coordinator = RecordingCoordinator(
            recording: recording,
            audio: audio,
            transcription: transcription,
            sentiment: sentiment,
            coaching: coaching,
            micVAD: micVAD,
            systemVAD: systemVAD,
            sentimentProvider: sentimentProvider,
            coachEngine: coachEngine,
            hybridSentiment: hybridSentiment,
            makeVAD: makeVAD,
            makeSentiment: makeSentiment,
            makeTranscriber: makeTranscriber
        )
    }
    
    // MARK: - Convenience Forwarding (for actions that touch multiple stores)
    
    func loadModel() async {
        await coordinator.loadModel()
    }
    
    func toggleRecording() async {
        await coordinator.toggleRecording()
    }
    
    func stopRecording() async {
        await coordinator.stopRecording()
    }
    
    func newSession() async {
        await coordinator.newSession()
    }
    
    func overrideMovement(_ movement: ConversationMovement) {
        coaching.overrideMovement(movement)
    }
    
    func toggleOverlay() {
        overlay.toggle()
    }

    func connectStreamingSTT(config: STTServerConfig = .default) async throws {
        try await coordinator.connectStreamingSTT(config: config)
        transcription.sttConnectionState = .connected
    }

    func disconnectStreamingSTT() {
        coordinator.disconnectStreamingSTT()
        transcription.sttConnectionState = .disconnected
    }
}
