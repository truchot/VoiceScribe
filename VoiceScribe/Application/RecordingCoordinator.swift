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
        micVAD: VADProvider,
        systemVAD: VADProvider,
        sentimentProvider: SentimentProvider,
        coachEngine: CoachingProvider,
        hybridSentiment: HybridSentimentProvider,
        makeVAD: @escaping (_ speechThreshold: Float) -> VADProvider,
        makeSentiment: @escaping (_ smoothingFactor: Float) -> SentimentProvider,
        makeTranscriber: @escaping (_ modelPath: String, _ language: String) -> TranscriberProvider
    ) {
        self.recording = recording
        self.audio = audio
        self.transcription = transcription
        self.sentiment = sentiment
        self.coaching = coaching
        
        // All components injected — no defaults here (composition root is AppEnvironment)
        self.micVAD = micVAD
        self.systemVAD = systemVAD
        self.whisperMic = nil
        self.whisperSystem = nil
        self.sentimentProvider = sentimentProvider
        self.coachEngine = coachEngine
        self.hybridSentiment = hybridSentiment
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
    }
    
    // MARK: - Model Loading
    
    /// Shared Voxtral context — kept alive so both transcribers share one model (~10.8 GB).
    private var voxtralContext: VoxtralContext?

    func loadModel() async {
        recording.setLoading()

        let engine = TranscriptionEngine(rawValue: transcription.engine) ?? .whisper
        let language = transcription.language

        // Unload previous engine
        whisperMic?.unloadModel()
        whisperSystem?.unloadModel()
        whisperMic = nil
        whisperSystem = nil
        voxtralContext = nil

        do {
            switch engine {
            case .whisper:
                guard let modelPath = findModelPath() else {
                    recording.setError("Modèle Whisper introuvable. Lancez ./setup.sh")
                    return
                }
                let t1 = makeTranscriber(modelPath, language)
                let t2 = makeTranscriber(modelPath, language)
                try await Task.detached(priority: .userInitiated) {
                    try t1.loadModel()
                    try t2.loadModel()
                }.value
                whisperMic = t1
                whisperSystem = t2

            case .voxtral:
                guard let modelDir = findVoxtralModelDir() else {
                    recording.setError("Modèle Voxtral introuvable. Lancez ./setup.sh voxtral")
                    return
                }
                let ctx = VoxtralContext()
                let config = VoxtralTranscriber.Config(modelDir: modelDir, language: language)
                let t1 = VoxtralTranscriber(config: config, sharedContext: ctx)
                let t2 = VoxtralTranscriber(config: config, sharedContext: ctx)
                try await Task.detached(priority: .userInitiated) {
                    try t1.loadModel()
                    try t2.loadModel()
                }.value
                voxtralContext = ctx
                whisperMic = t1
                whisperSystem = t2
            }

            recording.setReady()
            await audio.checkPermissions()
            if globalHotkeysEnabled { hotkeys.enable() }
        } catch {
            recording.setError(error.localizedDescription)
        }
    }
    
    // MARK: - Recording Lifecycle
    
    func startRecording() async {
        guard recording.state.canRecord else { return }
        
        // Session
        transcription.createSessionIfNeeded()
        
        // Reset coaching pipeline
        sentiment.reset()
        coaching.reset()
        coachEngine.reset()
        hybridSentiment.reset()
        
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
        
        // Start mic capture
        audio.audioCapture.configure(AudioCaptureManager.Config(chunkDuration: 0.5))
        audio.audioCapture.onAudioChunk = { [weak self] samples, time in
            guard let self else { return }
            self.micVAD.process(samples: samples, timestamp: time)
            var absSum: Float = 0
            vDSP_svemg(samples, 1, &absSum, vDSP_Length(samples.count))
            let level = absSum / Float(samples.count)
            Task { @MainActor in self.audio.updateMicLevel(level * 8.0) }
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
                        
                        // Feed text to hybrid sentiment (prospect speech only)
                        if speaker == .other {
                            self.hybridSentiment.feedText(
                                seg.text, speaker: speaker, timestamp: seg.startTime
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
                
                // Merge prosody × text for enriched commercial-aware emotion
                let hybrid = self.hybridSentiment.merge(
                    prosody: emotion,
                    at: features.timestamp
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
            
            // Push result back to MainActor
            Task { @MainActor [weak self] in
                self?.coaching.updateAdvice(output)
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
    
    private func findVoxtralModelDir() -> String? {
        let marker = "consolidated.safetensors"
        let candidates: [String] = [
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Models/voxtral-model").path,
            FileManager.default.currentDirectoryPath + "/Models/voxtral-model",
            NSHomeDirectory() + "/Sites/VoiceScribe/Models/voxtral-model",
            NSHomeDirectory() + "/VoiceScribe/Models/voxtral-model",
            NSHomeDirectory() + "/Developer/VoiceScribe/Models/voxtral-model"
        ]
        return candidates.first(where: {
            FileManager.default.fileExists(atPath: $0 + "/" + marker)
        })
    }

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
