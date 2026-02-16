import Foundation
import os

/// Centralized logging for VoiceScribe.
/// Uses os.Logger for structured, filterable, release-safe logging.
/// In Console.app: filter by subsystem "com.voicescribe" to see all logs.
enum Log {
    /// Audio pipeline (capture, VAD, levels)
    static let audio = Logger(subsystem: "com.voicescribe", category: "audio")
    
    /// Transcription (whisper model, segments)
    static let transcription = Logger(subsystem: "com.voicescribe", category: "transcription")
    
    /// Sentiment analysis (prosodic, text, hybrid)
    static let sentiment = Logger(subsystem: "com.voicescribe", category: "sentiment")
    
    /// Coaching engine (movement, memory, tips)
    static let coaching = Logger(subsystem: "com.voicescribe", category: "coaching")
    
    /// Persistence (SQLite, auto-save, flush)
    static let persistence = Logger(subsystem: "com.voicescribe", category: "persistence")
    
    /// Platform (hotkeys, permissions, overlay)
    static let platform = Logger(subsystem: "com.voicescribe", category: "platform")
}
