import Foundation
import SwiftUI

/// Focused observable for audio I/O state.
///
/// Owns the audio capture managers and exposes only the UI-relevant
/// state: levels, app selection, permissions.
///
/// Sentiment and coaching views don't re-render when audio levels change.
@MainActor
final class AudioStore: ObservableObject {
    
    // MARK: - Published State (UI-facing)
    
    @Published var micAudioLevel: Float = 0.0
    @Published var systemAudioLevel: Float = 0.0
    @Published var systemCaptureAvailable = false
    @Published var captureSystemAudio = true
    
    // MARK: - Settings
    
    @AppStorage("vadSensitivity") var vadSensitivity: Double = 0.5
    
    // MARK: - Owned Components
    
    let audioCapture = AudioCaptureManager()
    let systemAudio = SystemAudioCapture()
    
    var audioLevel: Float { max(micAudioLevel, systemAudioLevel) }
    
    // MARK: - Setup
    
    func checkPermissions() async {
        await systemAudio.checkPermission()
        await systemAudio.refreshAvailableApps()
        systemCaptureAvailable = systemAudio.permissionGranted
    }
    
    func refreshApps() async {
        await systemAudio.refreshAvailableApps()
    }
    
    // MARK: - Level Updates (called from coordinator)
    
    func updateMicLevel(_ level: Float) {
        micAudioLevel = min(1.0, level)
    }
    
    func updateSystemLevel(_ level: Float) {
        systemAudioLevel = min(1.0, level)
    }
    
    func resetLevels() {
        micAudioLevel = 0
        systemAudioLevel = 0
    }
}
