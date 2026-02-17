import Foundation

// MARK: - VAD Provider Protocol

/// Abstracts Voice Activity Detection.
/// Implementations: SileroVAD (heuristic), SileroONNXVAD (neural), MockVAD (tests)
protocol VADProvider: AnyObject {
    
    /// Called when a complete speech segment is detected (after silence).
    /// Provides the full audio samples and the timestamp of the segment start.
    var onSpeechSegment: ((_ samples: [Float], _ startTime: TimeInterval) -> Void)? { get set }
    
    /// Process incoming audio samples (16kHz mono Float32).
    func process(samples: [Float], timestamp: TimeInterval)
    
    /// Force emit any accumulated speech buffer.
    func flush()
    
    /// Reset all state for a new session.
    func reset()
}

// MARK: - Transcriber Provider Protocol

/// Abstracts speech-to-text transcription.
/// Implementations: WhisperTranscriber, MockTranscriber (tests)
protocol TranscriberProvider: AnyObject {
    
    /// Load the model into memory. Throws on failure.
    func loadModel() throws
    
    /// Unload the model from memory.
    func unloadModel()
    
    /// Transcribe audio samples asynchronously.
    /// Returns TranscriptionSegment (text, startTime, endTime, confidence).
    /// Speaker and sentiment are added later by the coordinator.
    func transcribe(
        samples: [Float],
        chunkTime: TimeInterval,
        completion: @escaping (Result<[TranscriptionSegment], Error>) -> Void
    )
}

// MARK: - Sentiment Provider Protocol

/// Abstracts real-time audio sentiment analysis.
/// Implementations: SentimentAnalyzer (prosodic), HybridSentimentAnalyzer (prosodic + text), MockSentiment (tests)
protocol SentimentProvider: AnyObject {
    
    /// Called periodically (~500ms) with updated emotional state.
    var onSentimentUpdate: ((EmotionalState, ProsodicFeatures) -> Void)? { get set }
    
    /// Called when a significant emotion shift is detected.
    var onSentimentShift: ((EmotionLabel, EmotionLabel) -> Void)? { get set }
    
    /// Process incoming audio samples for sentiment analysis.
    func process(samples: [Float], timestamp: TimeInterval)
    
    /// Reset all state.
    func reset()
}

// MARK: - Coaching Provider Protocol

/// Abstracts the coaching engine for testing and alternative implementations.
protocol CoachingProvider: AnyObject {
    
    /// Main coaching method — produce advice from current state.
    func coach(
        recentSegments: ArraySlice<TranscriptionSegment>,
        allSegments: [TranscriptionSegment],
        emotion: EmotionalState,
        elapsed: TimeInterval
    ) -> ConversationCoach.CoachingOutput
    
    /// Manual movement override.
    func overrideMovement(_ movement: ConversationMovement, at elapsed: TimeInterval)
    
    /// Manual memory entry.
    func setMemory(key: String, value: String, elapsed: TimeInterval)
    
    /// Generate post-call report.
    func generateReport(elapsed: TimeInterval) -> PostCallReport
    
    /// Reset all state.
    func reset()
    
    /// Current movement (read-only).
    var currentMovement: ConversationMovement { get }
    
    /// Access to conversation memory for UI.
    var conversationMemory: ConversationMemory { get }
    
    /// Domain event bus — set to wire persistence and analytics subscribers.
    var eventBus: CoachingEventBus? { get set }
}

// Conformance declared in Application/ProtocolConformances.swift

// MARK: - Persistence Provider Protocol

/// Abstracts session persistence for testing.
protocol PersistenceProvider: AnyObject {
    func saveSession(_ session: TranscriptionSession)
    func loadSession(id: UUID) -> TranscriptionSession?
    func loadSessionList() -> [TranscriptionSession]
    func deleteSession(id: UUID)
    func queueSegment(_ segment: TranscriptionSegment, sessionId: UUID)
    func search(query: String) -> [(session: TranscriptionSession, matchingText: String)]
    func startAutoSave(interval: TimeInterval)
    func stopAutoSave()
    func stats() -> (sessions: Int, segments: Int, dbSizeMB: Double)
}

// MARK: - Diarization Provider Protocol

/// Abstracts multi-speaker diarization (who is speaking when).
/// Implementations: SpeakerDiarizer (embedding-based), MockDiarizer (tests)
protocol DiarizationProvider: AnyObject {

    /// Called when a speaker change is detected.
    var onSpeakerChange: ((_ speaker: SpeakerProfile) -> Void)? { get set }

    /// Process incoming audio samples for speaker identification.
    func process(samples: [Float], timestamp: TimeInterval)

    /// Identify which speaker produced the given audio samples.
    func identifySpeaker(from samples: [Float]) -> SpeakerProfile?

    /// All currently known speakers.
    func currentSpeakers() -> [SpeakerProfile]

    /// Speaking time balance across speakers.
    func speakerBalance() -> SpeakerBalance

    /// Reset all speaker state for a new session.
    func reset()
}

// MARK: - Streaming Transcriber Provider Protocol

/// Abstracts streaming (WebSocket-based) speech-to-text for real-time partial results.
/// Implementations: WebSocketSTTClient, MockStreamingTranscriber (tests)
protocol StreamingTranscriberProvider: AnyObject {

    /// Called with partial (non-final) transcription updates.
    var onPartialResult: ((PartialTranscription) -> Void)? { get set }

    /// Called when a transcription segment is finalized.
    var onFinalResult: ((PartialTranscription) -> Void)? { get set }

    /// Current connection state.
    var connectionState: STTConnectionState { get }

    /// Connect to the remote STT server.
    func connect(config: STTServerConfig) async throws

    /// Disconnect from the server.
    func disconnect()

    /// Send audio samples for real-time transcription.
    func sendAudio(samples: [Float], timestamp: TimeInterval)
}

// MARK: - Semantic Sentiment Provider Protocol

/// Abstracts deep text semantic analysis (beyond keyword/pattern matching).
/// Implementations: SemanticSentimentAnalyzer, MockSemanticSentiment (tests)
protocol SemanticSentimentProvider: AnyObject {

    /// Analyze text semantically: intent, topics, sentiment.
    func analyze(text: String, speaker: Speaker, timestamp: TimeInterval) -> SemanticAnalysis

    /// Topics detected across the conversation so far.
    func recentTopics() -> [DetectedTopic]

    /// Detect conversational intent from a text snippet.
    func conversationIntent(from text: String) -> ConversationalIntent

    /// Reset all state.
    func reset()
}

// Conformances are in Application/ProtocolConformances.swift

// MARK: - LLM Provider Protocol

/// Abstracts LLM text generation for summaries and suggestions.
/// Implementations: LocalLLMProvider (template-based), APILLMProvider (Claude/OpenAI)
protocol LLMProvider: AnyObject {

    /// Generate text from a prompt.
    func generate(prompt: String, config: LLMConfig) async throws -> LLMResponse

    /// Generate a post-session summary from conversation data.
    func summarize(
        transcript: String,
        report: PostCallReport?,
        topics: [DetectedTopic],
        config: LLMConfig
    ) async throws -> SessionSummary

    /// Generate response suggestions based on current conversation context.
    func suggestResponse(
        recentText: String,
        movement: ConversationMovement,
        emotion: EmotionalState,
        topics: [DetectedTopic],
        config: LLMConfig
    ) async throws -> [ResponseSuggestion]
}

// MARK: - Analytics Provider Protocol

/// Abstracts cross-session analytics and semantic search.
/// Implementations: AnalyticsEngine
protocol AnalyticsProvider: AnyObject {

    /// Generate insights from cross-session data.
    func generateInsights() -> [ConversationInsight]

    /// Semantic search across all sessions.
    func semanticSearch(query: String) -> [SemanticSearchResult]

    /// Refresh analytics data from persistence.
    func refresh()
}

// MARK: - Hybrid Sentiment Provider Protocol

/// Abstracts text × prosody sentiment merging.
/// Implementations: HybridSentiment, MockHybridSentiment (tests)
protocol HybridSentimentProvider: AnyObject {
    
    /// Feed transcribed text for analysis.
    func feedText(_ text: String, speaker: Speaker, timestamp: TimeInterval)
    
    /// Merge prosodic analysis with recent text signals.
    func merge(prosody: EmotionalState, at timestamp: TimeInterval) -> HybridSentiment.HybridResult
    
    /// Reset all state.
    func reset()
}
