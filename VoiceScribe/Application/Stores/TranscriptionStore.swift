import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Focused observable for transcription data.
///
/// Manages sessions, segments, live text, persistence, and export.
/// Audio level changes and sentiment updates don't trigger re-renders here.
@MainActor
final class TranscriptionStore: ObservableObject {
    
    // MARK: - Published State
    
    @Published var currentSession: TranscriptionSession?
    @Published var liveTextMic: String = ""
    @Published var liveTextSystem: String = ""
    @Published private(set) var savedSessionCount: Int = 0
    
    /// True while Whisper is running inference on mic/system audio.
    /// UI can show a pulsing indicator during this window.
    @Published private(set) var isInferringMic: Bool = false
    @Published private(set) var isInferringSystem: Bool = false
    
    // MARK: - Settings
    
    @AppStorage("whisperLanguage") var language: String = "auto"
    @AppStorage("modelSize") var modelSize: String = "distil-large-v3"
    
    // MARK: - Dependencies
    
    private let persistence: PersistenceProvider
    
    var liveText: String {
        if !liveTextMic.isEmpty && !liveTextSystem.isEmpty { return liveTextMic }
        return liveTextMic.isEmpty ? liveTextSystem : liveTextMic
    }
    
    // MARK: - Init
    
    init(persistence: PersistenceProvider = SessionPersistence.shared) {
        self.persistence = persistence
        refreshStats()
    }
    
    // MARK: - Session Lifecycle
    
    func createSessionIfNeeded() {
        guard currentSession == nil else { return }
        let s = TranscriptionSession(
            title: "Session \(Date().formatted(date: .abbreviated, time: .shortened))"
        )
        currentSession = s
        persistence.saveSession(s)
    }
    
    func finishSession() {
        currentSession?.finish()
        if let s = currentSession {
            persistence.saveSession(s)
        }
        persistence.stopAutoSave()
        refreshStats()
    }
    
    func clearSession() {
        currentSession = nil
        liveTextMic = ""
        liveTextSystem = ""
    }
    
    func startAutoSave() {
        persistence.startAutoSave(interval: 30.0)
    }
    
    // MARK: - Segment Management
    
    /// Add a transcribed segment. Deduplication enforced by the aggregate.
    /// Returns true if the segment was accepted.
    @discardableResult
    func addSegment(_ segment: TranscriptionSegment) -> Bool {
        guard let accepted = currentSession?.addSegment(segment), accepted else {
            return false
        }
        if let sid = currentSession?.id {
            persistence.queueSegment(segment, sessionId: sid)
        }
        return true
    }
    
    /// Update live transcription text for a speaker.
    func setLiveText(_ text: String, speaker: Speaker) {
        switch speaker {
        case .me: liveTextMic = text
        case .other: liveTextSystem = text
        case .unknown: liveTextMic = text
        }
    }
    
    /// Track Whisper inference state for UI feedback (pulsing indicator).
    func setInferring(_ active: Bool, speaker: Speaker) {
        switch speaker {
        case .me, .unknown: isInferringMic = active
        case .other: isInferringSystem = active
        }
    }
    
    // MARK: - Persistence
    
    func loadSavedSession(id: UUID) {
        if let s = persistence.loadSession(id: id) {
            currentSession = s
        }
    }
    
    func savedSessions() -> [TranscriptionSession] {
        persistence.loadSessionList()
    }
    
    func searchTranscriptions(query: String) -> [(session: TranscriptionSession, matchingText: String)] {
        persistence.search(query: query)
    }
    
    func deleteSession(id: UUID) {
        persistence.deleteSession(id: id)
        if currentSession?.id == id { currentSession = nil }
        refreshStats()
    }
    
    func refreshStats() {
        savedSessionCount = persistence.stats().sessions
    }
    
    func persistenceStats() -> (sessions: Int, segments: Int, dbSizeMB: Double) {
        persistence.stats()
    }
    
    // MARK: - Export
    
    enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown"
        case srt = "SRT"
        case text = "Texte brut"
        case json = "JSON"
        case report = "Rapport Post-Call"
        
        var fileExtension: String {
            switch self {
            case .markdown, .report: return "md"
            case .srt: return "srt"
            case .text: return "txt"
            case .json: return "json"
            }
        }
        
        var contentType: UTType {
            switch self {
            case .json: return .json
            default: return .plainText
            }
        }
    }
    
    func exportSession(format: ExportFormat, report: PostCallReport? = nil) -> String? {
        guard let s = currentSession else { return nil }
        switch format {
        case .markdown: return s.exportMarkdown()
        case .srt: return s.exportSRT()
        case .text: return s.fullText
        case .json:
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            return (try? enc.encode(s)).flatMap { String(data: $0, encoding: .utf8) }
        case .report:
            return report?.toMarkdown()
        }
    }
    
    func saveSession(format: ExportFormat, report: PostCallReport? = nil) {
        guard let content = exportSession(format: format, report: report) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(currentSession?.title ?? "transcription").\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Log.persistence.error("Export write failed: \(error.localizedDescription)")
            }
        }
    }
    
}
