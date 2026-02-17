import Foundation
import Accelerate

/// Orchestrates the recording pipeline without being observable itself.
///
/// This is the "brain" that connects:
///   Mic Audio → micVAD → whisperMic → TranscriptionStore
///   Sys Audio → sysVAD → whisperSys → TranscriptionStore
///                      → sentiment  → SentimentStore → CoachingStore
///
/// Each store is a focused ObservableObject. The coordinator updates
/// them via their public methods. Views only observe the stores they need.
///
/// Components are injected via protocols, enabling testing and hot-swapping.
@MainActor
final class RecordingCoordinator {
    
    // MARK: - Stores (owned by AppEnvironment, shared with coordinator)
    
    let recording: RecordingStore
    let audio: AudioStore
    let transcription: TranscriptionStore
    let sentiment: SentimentStore
    let coaching: CoachingStore
    let summary: SummaryStore
    
    // MARK: - Pipeline Components (protocol-based, all injected)
    
    private var micVAD: VADProvider
    private var systemVAD: VADProvider
    private var whisperMic: TranscriberProvider?
    private var whisperSystem: TranscriberProvider?
    private var sentimentProvider: SentimentProvider
    private var coachEngine: CoachingProvider
    
    // MARK: - Factories (for components recreated per-session with runtime config)
    
    /// Creates a fresh VAD with the given speech threshold.
    let makeVAD: (_ speechThreshold: Float) -> VADProvider
    
    /// Creates a fresh sentiment analyzer with the given smoothing factor.
    let makeSentiment: (_ smoothingFactor: Float) -> SentimentProvider
    
    /// Creates a fresh transcriber pair with the given config.
    let makeTranscriber: (_ modelPath: String, _ language: String) -> TranscriberProvider
    
    // MARK: - Phase 2 Components (protocol-based)

    private var diarizer: DiarizationProvider
    private var streamingSTT: StreamingTranscriberProvider?
    private var semanticSentiment: SemanticSentimentProvider

    // MARK: - Infrastructure

    let hotkeys = GlobalHotkeyManager()
    private var hybridSentiment: HybridSentimentProvider
    private let coachingPersistence = CoachingPersistenceUseCase()
    private let eventBus = CoachingEventBus()
    private var lastEmittedAlertMessage: String?  // Dedup for alertDetected events
    
    /// Dedicated serial queue for coaching computation (off MainActor)
    private let coachingQueue = DispatchQueue(label: "com.voicescribe.coaching", qos: .userInitiated)
    /// Throttle: skip coaching updates if <500ms since last one
    private var lastCoachingUpdate: TimeInterval = 0
    private let coachingThrottle: TimeInterval = 0.5
    
    /// Read from UserDefaults instead of @AppStorage to avoid SwiftUI in Application layer
    private var globalHotkeysEnabled: Bool {
        UserDefaults.standard.object(forKey: "globalHotkeysEnabled") as? Bool ?? true
    }
    
    // MARK: - Init
    
    init(
        recording: RecordingStore,
        audio: AudioStore,
        transcription: TranscriptionStore,
        sentiment: SentimentStore,
        coaching: CoachingStore,
        summary: SummaryStore = SummaryStore(),
        micVAD: VADProvider,
        systemVAD: VADProvider,
        sentimentProvider: SentimentProvider,
        coachEngine: CoachingProvider,
        hybridSentiment: HybridSentimentProvider,
        diarizer: DiarizationProvider,
        streamingSTT: StreamingTranscriberProvider? = nil,
        semanticSentiment: SemanticSentimentProvider,
        makeVAD: @escaping (_ speechThreshold: Float) -> VADProvider,
        makeSentiment: @escaping (_ smoothingFactor: Float) -> SentimentProvider,
        makeTranscriber: @escaping (_ modelPath: String, _ language: String) -> TranscriberProvider
    ) {
        self.recording = recording
        self.audio = audio
        self.transcription = transcription
        self.sentiment = sentiment
        self.coaching = coaching
        self.summary = summary

        // All components injected — no defaults here (composition root is AppEnvironment)
        self.micVAD = micVAD
        self.systemVAD = systemVAD
        self.whisperMic = nil
        self.whisperSystem = nil
        self.sentimentProvider = sentimentProvider
        self.coachEngine = coachEngine
        self.hybridSentiment = hybridSentiment

        // Phase 2: diarization, streaming STT, semantic sentiment
        self.diarizer = diarizer
        self.streamingSTT = streamingSTT
        self.semanticSentiment = semanticSentiment

        self.makeVAD = makeVAD
        self.makeSentiment = makeSentiment
        self.makeTranscriber = makeTranscriber

        // Wire domain event bus: coach engine → persistence subscriber
        self.coachEngine.eventBus = eventBus
        coachingPersistence.subscribe(to: eventBus)

        // Wire coaching store to engine
        coaching.configure(coach: self.coachEngine)

        setupHotkeys()
        setupCoachingCallbacks()
        setupSentimentCallbacks()
        setupDiarizationCallbacks()
        setupStreamingSTTCallbacks()
    }
    
    /// Maximum audio reconnection attempts before giving up.
    private static let maxReconnectAttempts = 3
    private var reconnectAttempts = 0

    // MARK: - Model Loading (with fallback chain)

    func loadModel() async {
        recording.setLoading()

        // Use the fallback chain: tries distil-large-v3 first, then falls back
        let preferredSize = transcription.modelSize
        guard let modelPath = WhisperTranscriber.bestAvailableModelPath(preferredSize: preferredSize)
                ?? findModelPath() else {
            recording.setError("Aucun modèle trouvé. Lancez ./setup.sh distil-large-v3")
            return
        }

        let language = transcription.language

        do {
            let t1 = makeTranscriber(modelPath, language)
            let t2 = makeTranscriber(modelPath, language)

            try await Task.detached(priority: .userInitiated) {
                try t1.loadModel()
                try t2.loadModel()
            }.value

            whisperMic = t1
            whisperSystem = t2
            recording.setReady()

            // Log the loaded model name
            let modelName = (modelPath as NSString).lastPathComponent
                .replacingOccurrences(of: "ggml-", with: "")
                .replacingOccurrences(of: ".bin", with: "")
            Log.transcription.info("Active model: \(modelName) (language: \(language))")

            await audio.checkPermissions()
            if globalHotkeysEnabled { hotkeys.enable() }
        } catch {
            // If the preferred model fails, try the next one in the chain
            Log.transcription.warning("Model load failed: \(error.localizedDescription). Attempting fallback...")
            await loadModelWithFallback(excluding: modelPath)
        }
    }

    /// Try remaining models in the fallback chain after the primary fails.
    private func loadModelWithFallback(excluding failedPath: String) async {
        let language = transcription.language
        let modelDirs = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Models").path,
            FileManager.default.currentDirectoryPath + "/Models",
            NSHomeDirectory() + "/Sites/VoiceScribe/Models",
            NSHomeDirectory() + "/VoiceScribe/Models",
            NSHomeDirectory() + "/Developer/VoiceScribe/Models",
        ]

        for size in WhisperTranscriber.modelFallbackChain {
            let filename = "ggml-\(size).bin"
            for dir in modelDirs {
                let path = (dir as NSString).appendingPathComponent(filename)
                guard path != failedPath, FileManager.default.fileExists(atPath: path) else { continue }

                do {
                    let t1 = makeTranscriber(path, language)
                    let t2 = makeTranscriber(path, language)

                    try await Task.detached(priority: .userInitiated) {
                        try t1.loadModel()
                        try t2.loadModel()
                    }.value

                    whisperMic = t1
                    whisperSystem = t2
                    recording.setReady()
                    Log.transcription.info("Fallback model loaded: \(size)")

                    await audio.checkPermissions()
                    if globalHotkeysEnabled { hotkeys.enable() }
                    return
                } catch {
                    Log.transcription.warning("Fallback \(size) also failed: \(error.localizedDescription)")
                    continue
                }
            }
        }

        recording.setError("Aucun modèle n'a pu être chargé. Lancez ./setup.sh")
    }
    
    // MARK: - Recording Lifecycle
    
    func startRecording() async {
        guard recording.state.canRecord else { return }
        
        // Session
        transcription.createSessionIfNeeded()
        
        // Reset coaching pipeline
        sentiment.reset()
        coaching.reset()
        summary.reset()
        coachEngine.reset()
        hybridSentiment.reset()
        diarizer.reset()
        semanticSentiment.reset()
        
        // Start persistence tracking for this session
        if let sessionId = transcription.currentSession?.id {
            coachingPersistence.start(sessionId: sessionId)
        }
        lastEmittedAlertMessage = nil
        
        // Create fresh VADs with current sensitivity (via factory)
        micVAD = makeVAD(Float(audio.vadSensitivity))
        systemVAD = makeVAD(Float(audio.vadSensitivity))
        
        // Wire VAD → Whisper
        micVAD.onSpeechSegment = { [weak self] samples, time in
            self?.transcribeSpeech(samples: samples, time: time, speaker: .me)
        }
        systemVAD.onSpeechSegment = { [weak self] samples, time in
            self?.transcribeSpeech(samples: samples, time: time, speaker: .other)
        }
        
        // Reset sentiment provider with current smoothing (via factory)
        sentimentProvider = makeSentiment(Float(sentiment.sentimentSmoothing))
        setupSentimentCallbacks()
        
        // Start mic capture (with reconnection resilience)
        reconnectAttempts = 0
        audio.audioCapture.configure(AudioCaptureManager.Config(chunkDuration: 0.5))
        audio.audioCapture.onAudioChunk = { [weak self] samples, time in
            guard let self else { return }
            self.micVAD.process(samples: samples, timestamp: time)
            var absSum: Float = 0
            vDSP_svemg(samples, 1, &absSum, vDSP_Length(samples.count))
            let level = absSum / Float(samples.count)
            Task { @MainActor in self.audio.updateMicLevel(level * 8.0) }
        }
        audio.audioCapture.onCaptureInterrupted = { [weak self] in
            Task { @MainActor in
                self?.attemptMicReconnection()
            }
        }

        do {
            try audio.audioCapture.startCapturing()
        } catch {
            recording.setError("Micro: \(error.localizedDescription)")
            return
        }
        
        // Start system audio capture
        if audio.captureSystemAudio && audio.systemAudio.selectedApp != nil {
            audio.systemAudio.onAudioChunk = { [weak self] samples, time in
                guard let self else { return }
                self.systemVAD.process(samples: samples, timestamp: time)
                self.diarizer.process(samples: samples, timestamp: time)
                if self.sentiment.sentimentEnabled {
                    self.sentimentProvider.process(samples: samples, timestamp: time)
                }
                let level: Float = {
                    var absSum: Float = 0
                    vDSP_svemg(samples, 1, &absSum, vDSP_Length(samples.count))
                    return absSum / Float(samples.count)
                }()
                Task { @MainActor in self.audio.updateSystemLevel(level * 8.0) }
            }
            do {
                try await audio.systemAudio.startCapturing(chunkDuration: 0.5)
            } catch {
                recording.setError("Audio système indisponible.")
            }
        }
        
        transcription.startAutoSave()
        recording.setRecording()
    }
    
    func pauseRecording() async {
        guard recording.state == .recording else { return }
        micVAD.flush()
        systemVAD.flush()
        audio.audioCapture.stopCapturing()
        if audio.systemAudio.isCapturing { await audio.systemAudio.stopCapturing() }
        recording.setPaused()
    }
    
    func stopRecording() async {
        micVAD.flush()
        systemVAD.flush()
        try? await Task.sleep(nanoseconds: 500_000_000) // Let last segments complete
        audio.audioCapture.stopCapturing()
        if audio.systemAudio.isCapturing { await audio.systemAudio.stopCapturing() }
        
        // Persist final coaching state before closing session
        if coaching.coachingEnabled, let _ = transcription.currentSession {
            let elapsed = recording.currentElapsed
            let lastOutput = coaching.coachingOutput
            // Sync to ensure no in-flight coaching computation
            let report = coachingQueue.sync {
                coachEngine.generateReport(elapsed: elapsed)
            }
            coachingPersistence.flush(
                output: lastOutput,
                elapsed: elapsed,
                report: report
            )
        }
        
        // Disconnect streaming STT if active
        streamingSTT?.disconnect()

        // Auto-generate AI summary if enabled
        if summary.autoSummaryEnabled, let session = transcription.currentSession {
            let transcript = session.exportMarkdown()
            let topics = semanticSentiment.recentTopics()
            let finalReport = coaching.coachingEnabled
                ? coachingQueue.sync { coachEngine.generateReport(elapsed: recording.currentElapsed) }
                : nil
            Task {
                await summary.generateSummary(transcript: transcript, report: finalReport, topics: topics)
            }
        }

        transcription.finishSession()
        audio.resetLevels()
        recording.setStopped()
    }

    func toggleRecording() async {
        switch recording.state {
        case .recording: await pauseRecording()
        case .ready, .paused: await startRecording()
        default: break
        }
    }
    
    func newSession() async {
        if recording.state == .recording { await stopRecording() }
        transcription.clearSession()
        sentiment.reset()
        coaching.reset()
        summary.reset()
        diarizer.reset()
        semanticSentiment.reset()
    }
    
    // MARK: - VAD → Whisper → Stores
    
    private func transcribeSpeech(samples: [Float], time: TimeInterval, speaker: Speaker) {
        let whisper = speaker == .me ? whisperMic : whisperSystem
        guard let whisper else { return }
        
        let dur = Double(samples.count) / 16000.0
        Task { @MainActor in
            self.transcription.setInferring(true, speaker: speaker)
            self.transcription.setLiveText(
                "\(speaker == .me ? "🎤" : "🔊") \(String(format: "%.1f", dur))s...",
                speaker: speaker
            )
        }
        
        whisper.transcribe(samples: samples, chunkTime: time) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                
                self.transcription.setInferring(false, speaker: speaker)
                
                switch result {
                case .success(let segments):
                    let sentimentSnapshot: EmotionalState? =
                        speaker == .other ? self.sentiment.latestSystemEmotion : nil
                    
                    for seg in segments {
                        // Re-tag with speaker and sentiment
                        let tagged = TranscriptionSegment(
                            text: seg.text,
                            startTime: seg.startTime,
                            endTime: seg.endTime,
                            speaker: speaker,
                            confidence: seg.confidence,
                            sentiment: sentimentSnapshot
                        )
                        self.transcription.addSegment(tagged)
                        
                        // Feed text to hybrid sentiment + semantic analyzer
                        if speaker == .other {
                            self.hybridSentiment.feedText(
                                seg.text, speaker: speaker, timestamp: seg.startTime
                            )
                            // Semantic analysis (deeper than pattern matching)
                            let _ = self.semanticSentiment.analyze(
                                text: seg.text, speaker: speaker, timestamp: seg.startTime
                            )
                        }
                    }
                    
                    self.transcription.setLiveText(
                        segments.last?.text ?? "",
                        speaker: speaker
                    )
                    
                    // Trigger coaching update
                    self.updateCoaching()
                    
                case .failure(let err):
                    self.recording.setError("\(speaker.rawValue): \(err.localizedDescription)")
                    self.transcription.setLiveText("", speaker: speaker)
                }
            }
        }
    }
    
    // MARK: - Sentiment Pipeline
    
    private func setupSentimentCallbacks() {
        sentimentProvider.onSentimentUpdate = { [weak self] emotion, features in
            Task { @MainActor in
                guard let self else { return }
                
                // Always store raw prosodic features (for UI gauges)
                self.sentiment.updateSentiment(emotion: emotion, features: features)
                
                // 3-channel merge: prosody × text patterns × semantic
                // Protocol now exposes merge(prosody:semantic:at:) — no downcast needed.
                let semanticSnapshot: SemanticAnalysis? = self.semanticSentiment.recentTopics().isEmpty
                    ? nil
                    : self.semanticSentiment.analyze(
                        text: "", speaker: .other, timestamp: features.timestamp
                    )
                let hybrid = self.hybridSentiment.merge(
                    prosody: emotion, semantic: semanticSnapshot, at: features.timestamp
                )
                
                // If text contributed meaningfully, use the hybrid result
                if hybrid.dominantSource != .prosody {
                    self.sentiment.updateHybrid(hybrid)
                    
                    // Emit domain event for new commercial alerts
                    if let alert = hybrid.commercialAlert,
                       alert.message != self.lastEmittedAlertMessage {
                        self.lastEmittedAlertMessage = alert.message
                        self.eventBus.emit(.alertDetected(
                            alert: alert,
                            elapsed: self.recording.currentElapsed
                        ))
                    }
                }
            }
        }
        sentimentProvider.onSentimentShift = { [weak self] from, to in
            Task { @MainActor in
                self?.sentiment.reportShift(from: from, to: to)
            }
        }
    }
    
    // MARK: - Coaching Pipeline (offloaded from MainActor)
    
    private func updateCoaching() {
        guard coaching.coachingEnabled,
              let session = transcription.currentSession else { return }
        
        let elapsed = recording.currentElapsed
        
        // Throttle: skip if <500ms since last update
        guard elapsed - lastCoachingUpdate >= coachingThrottle else { return }
        lastCoachingUpdate = elapsed
        
        // Snapshot immutable data on MainActor before dispatching
        let recent = Array(session.recentSegments())
        let allSegments = session.segments
        let emotion = sentiment.currentEmotion
        
        // Heavy computation on background queue (not MainActor)
        coachingQueue.async { [weak self] in
            guard let self else { return }
            
            let output = self.coachEngine.coach(
                recentSegments: ArraySlice(recent),
                allSegments: allSegments,
                emotion: emotion,
                elapsed: elapsed
            )
            
            self.coachingPersistence.persistPeriodic(output: output, elapsed: elapsed)
            
            // Push result back to MainActor + trigger suggestions
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.coaching.updateAdvice(output)

                // Trigger LLM response suggestions
                let recentText = recent.map(\.text).joined(separator: " ")
                let movement = output.movement
                let currentEmotion = self.sentiment.currentEmotion
                let topics = self.semanticSentiment.recentTopics()
                await self.summary.generateSuggestions(
                    recentText: recentText,
                    movement: movement,
                    emotion: currentEmotion,
                    topics: topics,
                    elapsed: elapsed
                )
            }
        }
    }
    
    private func setupCoachingCallbacks() {
        coaching.onOverrideMovement = { [weak self] movement in
            guard let self else { return }
            let elapsed = self.recording.currentElapsed
            // Serialize with coachingQueue to avoid racing with updateCoaching
            self.coachingQueue.async {
                self.coachEngine.overrideMovement(movement, at: elapsed)
            }
            self.updateCoaching()
        }
        
        coaching.onSetMemorySlot = { [weak self] key, value in
            guard let self else { return }
            let elapsed = self.recording.currentElapsed
            self.coachingQueue.async {
                self.coachEngine.setMemory(key: key, value: value, elapsed: elapsed)
            }
            self.updateCoaching()
        }
        
        coaching.onGenerateReport = { [weak self] in
            guard let self else { return nil }
            let elapsed = self.recording.currentElapsed
            // Sync on coachingQueue: safe because caller is MainActor, not coachingQueue
            return self.coachingQueue.sync {
                self.coachEngine.generateReport(elapsed: elapsed)
            }
        }
        
        coaching.onExportReport = { [weak self] in
            guard let self else { return }
            let elapsed = self.recording.currentElapsed
            let report = self.coachingQueue.sync {
                self.coachEngine.generateReport(elapsed: elapsed)
            }
            self.transcription.saveSession(format: .report, report: report)
        }
    }
    
    // MARK: - Diarization Pipeline

    private func setupDiarizationCallbacks() {
        diarizer.onSpeakerChange = { [weak self] speaker in
            Task { @MainActor in
                guard let self else { return }
                let balance = self.diarizer.speakerBalance()
                self.transcription.updateSpeakerInfo(
                    activeSpeakers: self.diarizer.currentSpeakers(),
                    balance: balance
                )
            }
        }
    }

    // MARK: - Streaming STT Pipeline

    private func setupStreamingSTTCallbacks() {
        streamingSTT?.onPartialResult = { [weak self] partial in
            Task { @MainActor in
                self?.transcription.setLiveText(partial.text, speaker: .other)
            }
        }
        streamingSTT?.onFinalResult = { [weak self] partial in
            Task { @MainActor in
                guard let self else { return }
                let segment = partial.toSegment(speaker: .other, endTime: partial.timestamp + 3.0)
                self.transcription.addSegment(segment)
                self.hybridSentiment.feedText(partial.text, speaker: .other, timestamp: partial.timestamp)
                let _ = self.semanticSentiment.analyze(text: partial.text, speaker: .other, timestamp: partial.timestamp)
                self.updateCoaching()
            }
        }
    }

    /// Connect to a streaming STT server (e.g. Voxtral).
    func connectStreamingSTT(config: STTServerConfig) async throws {
        guard let stt = streamingSTT else { return }
        try await stt.connect(config: config)
        Log.transcription.info("Streaming STT connected: \(config.model) @ \(config.host):\(config.port)")
    }

    /// Disconnect from the streaming STT server.
    func disconnectStreamingSTT() {
        streamingSTT?.disconnect()
    }

    // MARK: - Audio Reconnection

    /// Attempt to reconnect the microphone after an interruption (e.g. device disconnected).
    /// Retries up to `maxReconnectAttempts` with exponential backoff.
    private func attemptMicReconnection() {
        guard recording.state == .recording else { return }
        guard reconnectAttempts < Self.maxReconnectAttempts else {
            recording.setError("Microphone déconnecté. Reconnexion échouée après \(Self.maxReconnectAttempts) tentatives.")
            return
        }

        reconnectAttempts += 1
        let attempt = reconnectAttempts
        let delay = Double(1 << attempt) // 2s, 4s, 8s exponential backoff

        Log.audio.warning("Microphone interrompu. Tentative de reconnexion \(attempt)/\(Self.maxReconnectAttempts) dans \(delay)s...")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard self.recording.state == .recording else { return }

            do {
                self.audio.audioCapture.stopCapturing()
                try self.audio.audioCapture.startCapturing()
                self.reconnectAttempts = 0
                Log.audio.info("Microphone reconnecté avec succès")
            } catch {
                Log.audio.warning("Reconnexion échouée: \(error.localizedDescription)")
                self.attemptMicReconnection()
            }
        }
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeys.onToggleRecording = { [weak self] in
            Task { @MainActor in await self?.toggleRecording() }
        }
        hotkeys.onStopRecording = { [weak self] in
            Task { @MainActor in await self?.stopRecording() }
        }
        hotkeys.onNewSession = { [weak self] in
            Task { @MainActor in await self?.newSession() }
        }
    }
    
    // MARK: - Model Path Resolution
    
    private func findModelPath() -> String? {
        let f = "ggml-\(transcription.modelSize).bin"
        let candidates: [String?] = [
            Bundle.main.path(forResource: f, ofType: nil),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Models/\(f)").path,
            FileManager.default.currentDirectoryPath + "/Models/\(f)",
            NSHomeDirectory() + "/Sites/VoiceScribe/Models/\(f)",
            NSHomeDirectory() + "/VoiceScribe/Models/\(f)",
            NSHomeDirectory() + "/Developer/VoiceScribe/Models/\(f)"
        ]
        return candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0)
        })
    }
}
