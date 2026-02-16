import Foundation
import SwiftUI

/// Focused observable for recording state.
///
/// Views that only need to know "are we recording?" observe this store
/// instead of the entire engine. State changes here don't trigger
/// re-renders in sentiment or coaching views.
@MainActor
final class RecordingStore: ObservableObject {
    
    // MARK: - State
    
    enum State: Equatable {
        case idle
        case loading
        case ready
        case recording
        case paused
        
        var isActive: Bool { self == .recording || self == .paused }
        var canRecord: Bool { self == .ready || self == .paused }
        var statusText: String {
            switch self {
            case .recording: return "● REC"
            case .paused: return "❚❚ PAUSE"
            case .ready: return "PRÊT"
            case .loading: return "CHARGEMENT..."
            case .idle: return "INACTIF"
            }
        }
        var statusColor: Color {
            switch self {
            case .recording: return .red
            case .paused: return .orange
            case .ready: return .green
            case .loading: return .yellow
            case .idle: return .gray
            }
        }
    }
    
    @Published private(set) var state: State = .idle
    @Published private(set) var modelLoaded: Bool = false
    @Published var error: String?
    
    /// Elapsed time since recording started (nil if not recording)
    @Published private(set) var elapsed: TimeInterval = 0
    
    private(set) var recordingStartTime: Date?
    private var elapsedTimer: Timer?
    
    // MARK: - State Transitions
    
    func setLoading() { state = .loading; error = nil }
    func setReady() { state = .ready; modelLoaded = true }
    func setIdle() { state = .idle }
    
    func setRecording() {
        if recordingStartTime == nil { recordingStartTime = Date() }
        state = .recording
        startElapsedTimer()
    }
    
    func setPaused() {
        state = .paused
        stopElapsedTimer()
    }
    
    func setStopped() {
        state = .ready
        stopElapsedTimer()
        recordingStartTime = nil
        elapsed = 0
    }
    
    func setError(_ message: String) {
        error = message
        if state == .loading { state = .idle }
    }
    
    /// Current elapsed seconds since recording started
    var currentElapsed: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return -start.timeIntervalSinceNow
    }
    
    // MARK: - Timer
    
    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsed = self?.currentElapsed ?? 0
            }
        }
    }
    
    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
