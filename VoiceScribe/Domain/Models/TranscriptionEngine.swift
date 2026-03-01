import Foundation

/// Available transcription engines.
enum TranscriptionEngine: String, CaseIterable {
    case whisper
    case voxtral

    var displayName: String {
        switch self {
        case .whisper: return "Whisper"
        case .voxtral: return "Voxtral"
        }
    }
}
