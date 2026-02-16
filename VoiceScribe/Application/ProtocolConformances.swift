import Foundation

// MARK: - SileroVAD → VADProvider
// All method signatures match exactly.
extension SileroVAD: VADProvider {}

// MARK: - SileroONNXVAD → VADProvider
// All method signatures match exactly.
extension SileroONNXVAD: VADProvider {}

// MARK: - SentimentAnalyzer → SentimentProvider
// Callbacks and process/reset signatures match exactly.
extension SentimentAnalyzer: SentimentProvider {}

// MARK: - WhisperTranscriber → TranscriberProvider
//
// WhisperTranscriber.transcribe returns Result<[TranscriptionSegment], WhisperError>
// Protocol requires Result<[TranscriptionSegment], Error>
// Swift covariance handles this: WhisperError conforms to Error,
// so the extension just declares conformance.
extension WhisperTranscriber: TranscriberProvider {}

// MARK: - ConversationCoach → CoachingProvider
extension ConversationCoach: CoachingProvider {}

// MARK: - SessionPersistence → PersistenceProvider
extension SessionPersistence: PersistenceProvider {}

// MARK: - HybridSentiment → HybridSentimentProvider
extension HybridSentiment: HybridSentimentProvider {}
