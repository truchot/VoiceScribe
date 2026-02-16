import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine

/// Captures system audio from specific applications (Teams, Zoom, Google Meet, etc.)
/// using ScreenCaptureKit (macOS 13+).
///
/// This allows hearing what OTHER participants say in a video call,
/// while AudioCaptureManager handles the local microphone.
@MainActor
final class SystemAudioCapture: NSObject, ObservableObject {
    
    // MARK: - Configuration
    
    /// Known video conferencing app bundle identifiers
    static let knownApps: [AppTarget] = [
        AppTarget(name: "Zoom", bundleIDs: ["us.zoom.xos"]),
        AppTarget(name: "Microsoft Teams", bundleIDs: [
            "com.microsoft.teams",
            "com.microsoft.teams2"          // New Teams app
        ]),
        AppTarget(name: "Google Chrome", bundleIDs: ["com.google.Chrome"]),
        AppTarget(name: "Safari", bundleIDs: ["com.apple.Safari"]),
        AppTarget(name: "Firefox", bundleIDs: ["org.mozilla.firefox"]),
        AppTarget(name: "Arc", bundleIDs: ["company.thebrowser.Browser"]),
        AppTarget(name: "Brave", bundleIDs: ["com.brave.Browser"]),
        AppTarget(name: "Microsoft Edge", bundleIDs: ["com.microsoft.edgemac"]),
        AppTarget(name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"]),
        AppTarget(name: "Discord", bundleIDs: ["com.heckel.discord"]),
        AppTarget(name: "FaceTime", bundleIDs: ["com.apple.FaceTime"]),
    ]
    
    struct AppTarget: Identifiable {
        let id = UUID()
        let name: String
        let bundleIDs: [String]
    }
    
    // MARK: - Published State
    
    @Published var isCapturing = false
    @Published var availableApps: [DetectedApp] = []
    @Published var selectedApp: DetectedApp?
    @Published var audioLevel: Float = 0.0
    @Published var error: String?
    @Published var permissionGranted = false
    
    struct DetectedApp: Identifiable, Hashable {
        let id: String  // bundleID
        let name: String
        let pid: pid_t
        let scApp: SCRunningApplication
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: DetectedApp, rhs: DetectedApp) -> Bool {
            lhs.id == rhs.id && lhs.pid == rhs.pid
        }
    }
    
    // MARK: - Audio Chunk Callback
    
    /// Called with PCM Float32 samples at 16kHz mono from the system audio source.
    var onAudioChunk: (([Float], TimeInterval) -> Void)?
    
    // MARK: - Private Properties
    
    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var sessionStartTime: Date?
    private var audioBuffer: [Float] = []
    private let bufferQueue = DispatchQueue(label: "com.voicescribe.system-audio-buffer", qos: .userInteractive)
    private var chunkDuration: TimeInterval = 3.0
    private var overlapDuration: TimeInterval = 0.5
    private let targetSampleRate: Double = 16000.0
    
    // Refresh timer
    private var refreshTimer: Timer?
    
    // MARK: - Permission Check
    
    func checkPermission() async {
        // ScreenCaptureKit will prompt the user automatically on first use.
        // We can pre-check by trying to get shareable content.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            permissionGranted = true
            updateAvailableApps(from: content)
        } catch {
            permissionGranted = false
            self.error = "Permission d'enregistrement d'écran requise. Allez dans Préférences Système → Confidentialité → Enregistrement d'écran."
        }
    }
    
    // MARK: - App Discovery
    
    /// Scan running applications for known video conferencing apps
    func refreshAvailableApps() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            updateAvailableApps(from: content)
        } catch {
            self.error = "Impossible de scanner les applications: \(error.localizedDescription)"
        }
    }
    
    private func updateAvailableApps(from content: SCShareableContent) {
        let knownBundleIDs = Set(Self.knownApps.flatMap { $0.bundleIDs })
        
        var detected: [DetectedApp] = []
        
        for app in content.applications {
            let bundleID = app.bundleIdentifier
            
            // Match against known apps
            if knownBundleIDs.contains(bundleID) {
                let name = Self.knownApps
                    .first { $0.bundleIDs.contains(bundleID) }?
                    .name ?? app.applicationName
                
                detected.append(DetectedApp(
                    id: bundleID,
                    name: name,
                    pid: app.processID,
                    scApp: app
                ))
            }
        }
        
        // Sort: prioritize dedicated apps over browsers
        detected.sort { a, b in
            let aIsBrowser = ["Chrome", "Safari", "Firefox", "Arc", "Brave", "Edge"].contains(where: { a.name.contains($0) })
            let bIsBrowser = ["Chrome", "Safari", "Firefox", "Arc", "Brave", "Edge"].contains(where: { b.name.contains($0) })
            if aIsBrowser != bIsBrowser { return !aIsBrowser }
            return a.name < b.name
        }
        
        self.availableApps = detected
        
        // Auto-select first non-browser app, or first app if all are browsers
        if selectedApp == nil || !detected.contains(where: { $0.id == selectedApp?.id }) {
            let preferredApp = detected.first { app in
                !["Chrome", "Safari", "Firefox", "Arc", "Brave", "Edge"]
                    .contains(where: { app.name.contains($0) })
            }
            selectedApp = preferredApp ?? detected.first
        }
        
        Log.audio.info("Detected \(detected.count) video apps")
    }
    
    // MARK: - Start / Stop Capture
    
    func startCapturing(app: DetectedApp? = nil, chunkDuration: TimeInterval = 3.0) async throws {
        guard !isCapturing else { return }
        
        let target = app ?? selectedApp
        guard let target = target else {
            throw CaptureError.noAppSelected
        }
        
        self.chunkDuration = chunkDuration
        
        // Get fresh shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        
        // Find the app in current content
        guard let scApp = content.applications.first(where: {
            $0.bundleIdentifier == target.id
        }) else {
            throw CaptureError.appNotRunning(target.name)
        }
        
        // Configure filter: capture ONLY audio from this specific app
        let filter = SCContentFilter(desktopIndependentWindow: content.windows.first { 
            $0.owningApplication?.bundleIdentifier == target.id 
        } ?? content.windows[0])
        
        // Actually, for audio-only capture, we use an app-level filter
        let appFilter = SCContentFilter(
            display: content.displays[0],
            including: [scApp],
            exceptingWindows: []
        )
        
        // Stream configuration: audio only
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Don't capture our own app sounds
        config.sampleRate = 48000   // SCK native rate, we downsample to 16kHz
        config.channelCount = 1     // Mono
        
        // Minimize video capture (we only want audio)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps minimum
        config.showsCursor = false
        
        // Create stream
        let stream = SCStream(filter: appFilter, configuration: config, delegate: nil)
        
        // Setup audio output
        let output = AudioStreamOutput(
            targetSampleRate: targetSampleRate,
            onSamples: { [weak self] samples in
                self?.handleIncomingSamples(samples)
            }
        )
        
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        
        self.stream = stream
        self.streamOutput = output
        self.sessionStartTime = Date()
        self.audioBuffer.removeAll()
        
        // Start the stream
        try await stream.startCapture()
        
        self.isCapturing = true
        self.selectedApp = target
        self.error = nil
        
        // Start periodic app refresh
        startRefreshTimer()
        
        Log.audio.info("System audio capture started for: \(target.name)")
    }
    
    func stopCapturing() async {
        guard isCapturing, let stream = stream else { return }
        
        stopRefreshTimer()
        
        do {
            try await stream.stopCapture()
        } catch {
            Log.audio.error("Error stopping stream: \(error)")
        }
        
        // Flush remaining buffer
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.audioBuffer.isEmpty {
                let chunk = self.audioBuffer
                let time = Date().timeIntervalSince(self.sessionStartTime ?? Date())
                self.onAudioChunk?(chunk, time)
                self.audioBuffer.removeAll()
            }
        }
        
        self.stream = nil
        self.streamOutput = nil
        self.isCapturing = false
        self.audioLevel = 0
        
        Log.audio.info("System audio capture stopped")
    }
    
    // MARK: - Private: Buffer Management
    
    private func handleIncomingSamples(_ samples: [Float]) {
        let chunkSamples = Int(chunkDuration * targetSampleRate)
        
        // Update level
        let level = calculateRMSLevel(samples)
        Task { @MainActor in
            self.audioLevel = level
        }
        
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioBuffer.append(contentsOf: samples)
            
            if self.audioBuffer.count >= chunkSamples {
                let chunk = Array(self.audioBuffer.prefix(chunkSamples))
                let overlapSamples = Int(self.overlapDuration * self.targetSampleRate)
                let removeCount = max(0, self.audioBuffer.count - overlapSamples)
                self.audioBuffer.removeFirst(min(removeCount, self.audioBuffer.count))
                
                let currentTime = Date().timeIntervalSince(self.sessionStartTime ?? Date())
                self.onAudioChunk?(chunk, currentTime)
            }
        }
    }
    
    private func calculateRMSLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        return min(1.0, rms * 4.0)
    }
    
    // MARK: - Refresh Timer
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAvailableApps()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Error Types
    
    enum CaptureError: LocalizedError {
        case noAppSelected
        case appNotRunning(String)
        case permissionDenied
        case streamError(String)
        
        var errorDescription: String? {
            switch self {
            case .noAppSelected:
                return "Aucune application sélectionnée. Choisissez l'app de visio à écouter."
            case .appNotRunning(let name):
                return "\(name) n'est pas en cours d'exécution."
            case .permissionDenied:
                return "Permission d'enregistrement d'écran refusée. Allez dans Préférences Système → Confidentialité → Enregistrement d'écran."
            case .streamError(let msg):
                return "Erreur de capture: \(msg)"
            }
        }
    }
}

// MARK: - SCStream Audio Output Handler

/// Handles the raw audio samples from ScreenCaptureKit and resamples to 16kHz.
private class AudioStreamOutput: NSObject, SCStreamOutput {
    
    private let targetSampleRate: Double
    private let onSamples: ([Float]) -> Void
    
    init(targetSampleRate: Double, onSamples: @escaping ([Float]) -> Void) {
        self.targetSampleRate = targetSampleRate
        self.onSamples = onSamples
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid else { return }
        guard let formatDescription = sampleBuffer.formatDescription else { return }
        
        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let asbd = audioStreamBasicDescription?.pointee else { return }
        
        let sourceSampleRate = asbd.mSampleRate
        let sourceChannels = Int(asbd.mChannelsPerFrame)
        
        // Extract PCM samples
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == noErr, let data = dataPointer else { return }
        
        // Interpret as Float32
        let floatCount = length / MemoryLayout<Float>.size
        let floatPointer = data.withMemoryRebound(to: Float.self, capacity: floatCount) { ptr in
            Array(UnsafeBufferPointer(start: ptr, count: floatCount))
        }
        
        // Mix to mono if stereo
        var monoSamples: [Float]
        if sourceChannels > 1 {
            let frameCount = floatCount / sourceChannels
            monoSamples = [Float](repeating: 0, count: frameCount)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<sourceChannels {
                    sum += floatPointer[frame * sourceChannels + ch]
                }
                monoSamples[frame] = sum / Float(sourceChannels)
            }
        } else {
            monoSamples = floatPointer
        }
        
        // Resample to 16kHz if needed
        if abs(sourceSampleRate - targetSampleRate) > 1.0 {
            monoSamples = resample(monoSamples, from: sourceSampleRate, to: targetSampleRate)
        }
        
        onSamples(monoSamples)
    }
    
    /// Simple linear interpolation resampler (good enough for speech)
    private func resample(_ samples: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = sourceSR / targetSR
        let outputLength = Int(Double(samples.count) / ratio)
        guard outputLength > 0 else { return [] }
        
        var output = [Float](repeating: 0, count: outputLength)
        
        for i in 0..<outputLength {
            let sourceIndex = Double(i) * ratio
            let index = Int(sourceIndex)
            let fraction = Float(sourceIndex - Double(index))
            
            if index + 1 < samples.count {
                output[i] = samples[index] * (1.0 - fraction) + samples[index + 1] * fraction
            } else if index < samples.count {
                output[i] = samples[index]
            }
        }
        
        return output
    }
}
