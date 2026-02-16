import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Main engine — orchestrates all pipelines:
///
/// LAYER 1: Audio → VAD → Whisper → Segments
/// LAYER 2: Audio → Sentiment Analyzer (~50ms) → Empathetic Coach
/// LAYER 3: Segments → Phase Detector → Commercial Coach
@MainActor
final class TranscriptionEngine: ObservableObject {
    
    // MARK: - Published State
    
    @Published var state: EngineState = .idle
    @Published var currentSession: TranscriptionSession?
    @Published var liveTextMic: String = ""
    @Published var liveTextSystem: String = ""
    @Published var micAudioLevel: Float = 0.0
    @Published var systemAudioLevel: Float = 0.0
    @Published var error: String?
    @Published var modelLoaded: Bool = false
    
    // System audio
    @Published var systemCaptureAvailable = false
    @Published var captureSystemAudio = true
    
    // Layer 2: Sentiment + Empathetic Coach
    @Published var currentEmotion = EmotionalState()
    @Published var currentFeatures = ProsodicFeatures()
    @Published var sentimentTimeline: [SentimentPoint] = []
    @Published var lastSentimentShift: (from: EmotionLabel, to: EmotionLabel)?
    @Published var sentimentEnabled = true
    @Published var currentSuggestion: CoachingSuggestionEngine.CoachingSuggestion?
    
    // Layer 3: Phase Detection + Commercial Coach
    @Published var currentAdvice: CommercialCoachEngine.CommercialAdvice?
    @Published var currentPhase: SalesPhaseDetector.SalesPhase = .ouverture
    @Published var coachingEnabled = true
    @Published var commercialCoachEnabled = true
    
    // Persistence
    @Published var savedSessionCount: Int = 0
    
    // Convenience
    var audioLevel: Float { max(micAudioLevel, systemAudioLevel) }
    var liveText: String {
        if !liveTextMic.isEmpty && !liveTextSystem.isEmpty { return liveTextMic }
        return liveTextMic.isEmpty ? liveTextSystem : liveTextMic
    }
    
    // MARK: - Settings
    
    @AppStorage("whisperLanguage") var language: String = "fr"
    @AppStorage("modelSize") var modelSize: String = "large-v3-turbo"
    @AppStorage("globalHotkeysEnabled") var globalHotkeysEnabled: Bool = true
    @AppStorage("vadSensitivity") var vadSensitivity: Double = 0.5
    @AppStorage("sentimentSmoothingFactor") var sentimentSmoothing: Double = 0.7
    
    // MARK: - Sub-components
    
    let audioCapture = AudioCaptureManager()
    let systemAudio = SystemAudioCapture()
    let hotkeys = GlobalHotkeyManager()
    private let persistence = SessionPersistence.shared
    
    private var micVAD = SileroVAD()
    private var systemVAD = SileroVAD()
    private var sentimentAnalyzer = SentimentAnalyzer()
    private var empatheticCoach = CoachingSuggestionEngine()
    private var phaseDetector = SalesPhaseDetector()
    private var commercialCoach = CommercialCoachEngine()
    
    private var whisperMic: WhisperTranscriber?
    private var whisperSystem: WhisperTranscriber?
    
    private var cancellables = Set<AnyCancellable>()
    private var latestSystemEmotion = EmotionalState()
    private var previousEmotionLabel: EmotionLabel? = nil
    private var recordingStartTime: Date?
    
    enum EngineState: Equatable {
        case idle, loading, ready, recording, paused
    }
    
    // MARK: - Init
    
    init() {
        setupBindings()
        setupHotkeys()
        setupSentiment()
        refreshStats()
    }
    
    // MARK: - Model Management
    
    func loadModel() async {
        state = .loading; error = nil
        guard let modelPath = findModelPath() else {
            error = "Modèle introuvable. Lancez ./setup.sh pour le télécharger."; state = .idle; return
        }
        let config = WhisperTranscriber.Config(modelPath: modelPath, language: language)
        do {
            let t1 = WhisperTranscriber(config: config)
            let t2 = WhisperTranscriber(config: config)
            try await Task.detached(priority: .userInitiated) { try t1.loadModel(); try t2.loadModel() }.value
            whisperMic = t1; whisperSystem = t2; modelLoaded = true; state = .ready
            await systemAudio.checkPermission()
            await systemAudio.refreshAvailableApps()
            systemCaptureAvailable = systemAudio.permissionGranted
            if globalHotkeysEnabled { hotkeys.enable() }
        } catch { self.error = error.localizedDescription; state = .idle }
    }
    
    // MARK: - Recording
    
    func startRecording() async {
        guard state == .ready || state == .paused else { return }
        
        if currentSession == nil {
            let s = TranscriptionSession(title: "Session \(Date().formatted(date: .abbreviated, time: .shortened))")
            currentSession = s; persistence.saveSession(s)
        }
        
        recordingStartTime = recordingStartTime ?? Date()
        
        // Reset all coaching layers
        sentimentAnalyzer.reset(); empatheticCoach.reset()
        phaseDetector.reset(); commercialCoach.reset()
        sentimentTimeline.removeAll(); currentEmotion = EmotionalState()
        currentSuggestion = nil; currentAdvice = nil; currentPhase = .ouverture
        previousEmotionLabel = nil
        
        // VADs
        let vadConfig = SileroVAD.Config(speechThreshold: Float(vadSensitivity))
        micVAD = SileroVAD(config: vadConfig); systemVAD = SileroVAD(config: vadConfig)
        micVAD.onSpeechSegment = { [weak self] s, t in self?.transcribeSpeech(samples: s, time: t, speaker: .me) }
        systemVAD.onSpeechSegment = { [weak self] s, t in self?.transcribeSpeech(samples: s, time: t, speaker: .other) }
        
        // Sentiment
        sentimentAnalyzer = SentimentAnalyzer(config: .init(smoothingFactor: Float(sentimentSmoothing)))
        setupSentiment()
        
        // Mic
        audioCapture.configure(AudioCaptureManager.Config(chunkDuration: 0.5))
        audioCapture.onAudioChunk = { [weak self] samples, time in
            guard let self else { return }
            self.micVAD.process(samples: samples, timestamp: time)
            let e = samples.reduce(0) { $0 + abs($1) } / Float(samples.count)
            Task { @MainActor in self.micAudioLevel = min(1.0, e * 8.0) }
        }
        do { try audioCapture.startCapturing() }
        catch { self.error = "Micro: \(error.localizedDescription)"; return }
        
        // System audio → VAD + Sentiment
        if captureSystemAudio && systemAudio.selectedApp != nil {
            systemAudio.onAudioChunk = { [weak self] samples, time in
                guard let self else { return }
                self.systemVAD.process(samples: samples, timestamp: time)
                if self.sentimentEnabled { self.sentimentAnalyzer.process(samples: samples, timestamp: time) }
                let e = samples.reduce(0) { $0 + abs($1) } / Float(samples.count)
                Task { @MainActor in self.systemAudioLevel = min(1.0, e * 8.0) }
            }
            do { try await systemAudio.startCapturing(chunkDuration: 0.5) }
            catch { self.error = "Audio système indisponible. Le micro fonctionne." }
        }
        
        persistence.startAutoSave(interval: 30.0)
        state = .recording
    }
    
    func pauseRecording() async {
        guard state == .recording else { return }
        micVAD.flush(); systemVAD.flush()
        audioCapture.stopCapturing()
        if systemAudio.isCapturing { await systemAudio.stopCapturing() }
        state = .paused
    }
    
    func stopRecording() async {
        micVAD.flush(); systemVAD.flush()
        try? await Task.sleep(nanoseconds: 500_000_000)
        audioCapture.stopCapturing()
        if systemAudio.isCapturing { await systemAudio.stopCapturing() }
        if var s = currentSession { s.endDate = Date(); currentSession = s; persistence.saveSession(s) }
        persistence.stopAutoSave(); refreshStats()
        state = .ready; liveTextMic = ""; liveTextSystem = ""
        recordingStartTime = nil
    }
    
    func toggleRecording() async {
        switch state {
        case .recording: await pauseRecording()
        case .ready, .paused: await startRecording()
        default: break
        }
    }
    
    // MARK: - VAD → Whisper → Phase Detection
    
    private func transcribeSpeech(samples: [Float], time: TimeInterval, speaker: Speaker) {
        let whisper = speaker == .me ? whisperMic : whisperSystem
        guard let whisper else { return }
        let dur = Double(samples.count) / 16000.0
        Task { @MainActor in
            if speaker == .me { self.liveTextMic = "🎤 \(String(format: "%.1f", dur))s..." }
            else { self.liveTextSystem = "🔊 \(String(format: "%.1f", dur))s..." }
        }
        whisper.transcribe(samples: samples, chunkTime: time) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let segments):
                    let sentiment: EmotionalState? = speaker == .other ? self.latestSystemEmotion : nil
                    let tagged = segments.map {
                        TranscriptionSegment(text: $0.text, startTime: $0.startTime, endTime: $0.endTime,
                                             speaker: speaker, confidence: $0.confidence, sentiment: sentiment)
                    }
                    for seg in tagged {
                        if let last = self.currentSession?.segments.last,
                           last.speaker == seg.speaker,
                           self.similarity(last.text, seg.text) > 0.85 { continue }
                        self.currentSession?.segments.append(seg)
                        if let sid = self.currentSession?.id { self.persistence.queueSegment(seg, sessionId: sid) }
                    }
                    if speaker == .me { self.liveTextMic = tagged.last?.text ?? "" }
                    else { self.liveTextSystem = tagged.last?.text ?? "" }
                    
                    // === LAYER 3: Phase detection + Commercial advice ===
                    self.updateCommercialCoaching()
                    
                case .failure(let err):
                    self.error = "\(speaker.rawValue): \(err.localizedDescription)"
                    if speaker == .me { self.liveTextMic = "" } else { self.liveTextSystem = "" }
                }
            }
        }
    }
    
    // MARK: - Layer 2: Sentiment → Empathetic Coach
    
    private func setupSentiment() {
        sentimentAnalyzer.onSentimentUpdate = { [weak self] emotion, features in
            Task { @MainActor in
                guard let self else { return }
                self.currentEmotion = emotion
                self.currentFeatures = features
                self.latestSystemEmotion = emotion
                
                let point = SentimentPoint(
                    timestamp: features.timestamp, emotion: emotion,
                    features: SentimentPointFeatures(
                        energy: features.rmsEnergy, pitchHz: features.pitchHz,
                        pitchContour: features.pitchContour, speechRate: features.speechRate,
                        pauseDuration: features.pauseDuration
                    )
                )
                self.sentimentTimeline.append(point)
                if self.sentimentTimeline.count > 600 { self.sentimentTimeline.removeFirst(self.sentimentTimeline.count - 600) }
                
                // Empathetic suggestion
                if self.coachingEnabled {
                    if let s = self.empatheticCoach.suggest(emotion: emotion, previousEmotion: self.previousEmotionLabel, timestamp: features.timestamp) {
                        self.currentSuggestion = s
                    }
                }
                self.previousEmotionLabel = emotion.label
            }
        }
        sentimentAnalyzer.onSentimentShift = { [weak self] from, to in
            Task { @MainActor in self?.lastSentimentShift = (from: from, to: to) }
        }
    }
    
    // MARK: - Layer 3: Phase Detection → Commercial Coach
    
    private func updateCommercialCoaching() {
        guard commercialCoachEnabled, let session = currentSession else { return }
        
        let elapsed = -(recordingStartTime ?? Date()).timeIntervalSinceNow
        let recentSegments = Array(session.segments.suffix(20))
        
        let phaseResult = phaseDetector.detect(
            recentSegments: recentSegments,
            allSegments: session.segments,
            currentEmotion: currentEmotion,
            elapsedTime: elapsed
        )
        
        currentPhase = phaseResult.currentPhase
        
        let advice = commercialCoach.advise(
            phaseResult: phaseResult,
            recentSegments: recentSegments,
            emotion: currentEmotion
        )
        
        currentAdvice = advice
    }
    
    /// Manual phase override (user clicks on phase bar)
    func overridePhase(_ phase: SalesPhaseDetector.SalesPhase) {
        let elapsed = -(recordingStartTime ?? Date()).timeIntervalSinceNow
        phaseDetector.setPhase(phase, at: elapsed)
        currentPhase = phase
        updateCommercialCoaching()
    }
    
    // MARK: - Session Management
    
    func newSession() async {
        if state == .recording { await stopRecording() }
        currentSession = nil; liveTextMic = ""; liveTextSystem = ""
        sentimentTimeline.removeAll(); currentEmotion = EmotionalState()
        currentSuggestion = nil; currentAdvice = nil; currentPhase = .ouverture
    }
    
    func loadSavedSession(id: UUID) { if let s = persistence.loadSession(id: id) { currentSession = s } }
    func savedSessions() -> [TranscriptionSession] { persistence.loadSessionList() }
    func searchTranscriptions(query: String) -> [(session: TranscriptionSession, matchingText: String)] { persistence.search(query: query) }
    func deleteSession(id: UUID) {
        persistence.deleteSession(id: id)
        if currentSession?.id == id { currentSession = nil }
        refreshStats()
    }
    
    func exportSession(format: ExportFormat) -> String? {
        guard let s = currentSession else { return nil }
        switch format {
        case .markdown: return s.exportMarkdown()
        case .srt: return s.exportSRT()
        case .text: return s.fullText
        case .json:
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
            return (try? enc.encode(s)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
    
    func saveSession(format: ExportFormat) {
        guard let content = exportSession(format: format) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(currentSession?.title ?? "transcription").\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        if panel.runModal() == .OK, let url = panel.url { try? content.write(to: url, atomically: true, encoding: .utf8) }
    }
    
    // MARK: - Hotkeys
    
    private func setupHotkeys() {
        hotkeys.onToggleRecording = { [weak self] in Task { @MainActor in await self?.toggleRecording() } }
        hotkeys.onStopRecording = { [weak self] in Task { @MainActor in await self?.stopRecording() } }
        hotkeys.onNewSession = { [weak self] in Task { @MainActor in await self?.newSession() } }
    }
    
    // MARK: - Helpers
    
    private func similarity(_ a: String, _ b: String) -> Double {
        let aL = a.lowercased(), bL = b.lowercased()
        if aL == bL { return 1.0 }; let m = max(a.count, b.count); if m == 0 { return 1.0 }
        return Double(zip(aL, bL).prefix(while: { $0 == $1 }).count) / Double(m)
    }
    private func setupBindings() {
        audioCapture.$audioLevel.receive(on: DispatchQueue.main).assign(to: &$micAudioLevel)
        systemAudio.$audioLevel.receive(on: DispatchQueue.main).assign(to: &$systemAudioLevel)
    }
    private func refreshStats() { savedSessionCount = persistence.stats().sessions }
    private func findModelPath() -> String? {
        let f = "ggml-\(modelSize).bin"
        if let p = Bundle.main.path(forResource: f, ofType: nil) { return p }
        let d = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Models/\(f)")
        if FileManager.default.fileExists(atPath: d.path) { return d.path }
        for p in [FileManager.default.currentDirectoryPath + "/Models/\(f)",
                  NSHomeDirectory() + "/VoiceScribe/Models/\(f)",
                  NSHomeDirectory() + "/Developer/VoiceScribe/Models/\(f)"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }; return nil
    }
    
    enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown", srt = "SRT", text = "Texte brut", json = "JSON"
        var fileExtension: String { switch self { case .markdown: "md"; case .srt: "srt"; case .text: "txt"; case .json: "json" } }
        var contentType: UTType { switch self { case .json: .json; default: .plainText } }
    }
}
