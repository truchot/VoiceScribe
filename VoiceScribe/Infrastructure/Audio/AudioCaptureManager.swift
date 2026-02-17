import AVFoundation
import Combine

/// Manages audio capture from the microphone using AVAudioEngine.
/// Buffers audio into chunks and emits them for transcription.
final class AudioCaptureManager: ObservableObject {
    
    // MARK: - Configuration
    
    struct Config {
        /// Duration of each audio chunk sent to Whisper (in seconds)
        var chunkDuration: TimeInterval = 3.0
        /// Overlap between chunks to avoid cutting words (in seconds)
        var overlapDuration: TimeInterval = 0.5
        /// Target sample rate for Whisper (always 16kHz)
        let sampleRate: Double = 16000.0
        /// Mono audio for Whisper
        let channels: AVAudioChannelCount = 1
    }
    
    // MARK: - Published State
    
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0.0  // 0.0 to 1.0 for VU meter
    @Published var error: String?
    
    // MARK: - Audio Chunk Callback

    /// Called when a new audio chunk is ready for transcription.
    /// Provides PCM Float32 samples at 16kHz mono.
    var onAudioChunk: (([Float], TimeInterval) -> Void)?

    /// Called when audio capture is interrupted (e.g. microphone disconnected).
    /// The coordinator should attempt reconnection when this fires.
    var onCaptureInterrupted: (() -> Void)?

    // MARK: - Private Properties

    private let engine = AVAudioEngine()
    private var config = Config()
    private var audioBuffer: [Float] = []
    private var sessionStartTime: Date?
    private var lastChunkTime: TimeInterval = 0
    private let bufferQueue = DispatchQueue(label: "com.voicescribe.audio-buffer", qos: .userInteractive)
    
    // MARK: - Public API
    
    func configure(_ config: Config) {
        self.config = config
    }
    
    func startCapturing() throws {
        guard !isCapturing else { return }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else {
            throw AudioError.noInputDevice
        }
        
        // Target format: 16kHz mono Float32 (what Whisper expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: config.sampleRate,
            channels: config.channels,
            interleaved: false
        ) else {
            throw AudioError.formatError
        }
        
        // Install converter if needed
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
        // Tap the input node
        let chunkSamples = Int(config.chunkDuration * config.sampleRate)
        
        sessionStartTime = Date()
        audioBuffer.removeAll()
        audioBuffer.reserveCapacity(chunkSamples * 2)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Convert to 16kHz mono if needed
            let samples: [Float]
            if let converter = converter {
                samples = self.convertBuffer(buffer, using: converter, targetFormat: targetFormat)
            } else {
                samples = self.extractSamples(from: buffer)
            }
            
            guard !samples.isEmpty else { return }
            
            // Update audio level for VU meter
            let level = self.calculateRMSLevel(samples)
            DispatchQueue.main.async {
                self.audioLevel = level
            }
            
            // Accumulate samples
            self.bufferQueue.async {
                self.audioBuffer.append(contentsOf: samples)
                
                // Emit chunk when we have enough samples
                if self.audioBuffer.count >= chunkSamples {
                    let chunk = Array(self.audioBuffer.prefix(chunkSamples))
                    
                    // Keep overlap for next chunk
                    let overlapSamples = Int(self.config.overlapDuration * self.config.sampleRate)
                    let removeCount = max(0, self.audioBuffer.count - overlapSamples)
                    self.audioBuffer.removeFirst(min(removeCount, self.audioBuffer.count))
                    
                    let currentTime = Date().timeIntervalSince(self.sessionStartTime ?? Date())
                    self.onAudioChunk?(chunk, currentTime)
                    self.lastChunkTime = currentTime
                }
            }
        }
        
        // Listen for audio interruptions (mic disconnect, Bluetooth switch, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isCapturing else { return }
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .began {
                Log.audio.warning("Audio capture interrupted")
                self.onCaptureInterrupted?()
            }
        }

        // Also handle the AVAudioEngine configuration change (e.g. device unplug)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isCapturing else { return }
            Log.audio.warning("Audio engine configuration changed (device change)")
            self.onCaptureInterrupted?()
        }

        engine.prepare()
        try engine.start()

        DispatchQueue.main.async {
            self.isCapturing = true
            self.error = nil
        }
    }
    
    func stopCapturing() {
        guard isCapturing else { return }

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        // Flush remaining buffer
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.audioBuffer.isEmpty {
                let chunk = self.audioBuffer
                let currentTime = Date().timeIntervalSince(self.sessionStartTime ?? Date())
                self.onAudioChunk?(chunk, currentTime)
                self.audioBuffer.removeAll()
            }
        }
        
        DispatchQueue.main.async {
            self.isCapturing = false
            self.audioLevel = 0
        }
    }
    
    /// Force flush current buffer (e.g., when user pauses)
    func flushBuffer() {
        bufferQueue.async { [weak self] in
            guard let self = self, !self.audioBuffer.isEmpty else { return }
            let chunk = self.audioBuffer
            let currentTime = Date().timeIntervalSince(self.sessionStartTime ?? Date())
            self.onAudioChunk?(chunk, currentTime)
            self.audioBuffer.removeAll()
        }
    }
    
    // MARK: - Private Helpers
    
    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> [Float] {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else { return [] }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard status != .error, error == nil else { return [] }
        
        return extractSamples(from: outputBuffer)
    }
    
    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }
    
    private func calculateRMSLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        // Normalize to 0-1 range (assuming max RMS of ~0.5 for speech)
        return min(1.0, rms * 4.0)
    }
    
    // MARK: - Error Types
    
    enum AudioError: LocalizedError {
        case noInputDevice
        case formatError
        case captureError(String)
        
        var errorDescription: String? {
            switch self {
            case .noInputDevice:
                return "Aucun microphone détecté. Vérifiez vos Préférences Système."
            case .formatError:
                return "Format audio non supporté."
            case .captureError(let msg):
                return "Erreur de capture: \(msg)"
            }
        }
    }
}
