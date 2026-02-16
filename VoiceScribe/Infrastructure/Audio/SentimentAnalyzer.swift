import Foundation
import Accelerate

/// Real-time audio sentiment analysis via prosodic features.
///
/// This is the "fast channel" — it analyzes raw audio in ~50ms
/// WITHOUT waiting for transcription. It extracts:
/// - Pitch (F0) via YIN algorithm → questions, confidence, stress
/// - Energy dynamics → engagement, emphasis
/// - Speech rate → nervousness, excitement
/// - Pause patterns → hesitation, reflection
/// - Spectral features → vocal effort, tension
///
/// These map to emotional dimensions (valence, arousal, dominance)
/// which then produce commercial signals for the coaching UI.
///
/// Processes 16kHz mono Float32 audio in 30ms frames with 10ms hop.
final class SentimentAnalyzer {
    
    // MARK: - Configuration
    
    struct Config {
        var sampleRate: Float = 16000
        var frameSize: Int = 480          // 30ms at 16kHz
        var hopSize: Int = 160            // 10ms hop
        var smoothingFactor: Float = 0.7  // EMA smoothing for output
        var emitInterval: TimeInterval = 0.5  // Emit sentiment point every 500ms
        
        // Pitch detection
        var minPitch: Float = 60          // Hz — lowest expected pitch
        var maxPitch: Float = 500         // Hz — highest expected pitch
        
        // Adaptive thresholds
        var energyFloor: Float = 0.001    // Below this = silence
        var pitchConfidenceThreshold: Float = 0.3
    }
    
    // MARK: - Callbacks
    
    /// Called every ~500ms with updated emotional state
    var onSentimentUpdate: ((EmotionalState, ProsodicFeatures) -> Void)?
    
    /// Called when a significant sentiment shift is detected
    var onSentimentShift: ((EmotionLabel, EmotionLabel) -> Void)?
    
    // MARK: - Properties
    
    private let config: Config
    private let analysisQueue = DispatchQueue(label: "com.voicescribe.sentiment", qos: .userInteractive)
    
    // Frame buffer
    private var frameBuffer = AudioFrameBuffer(capacity: 16384)
    
    // Running statistics for adaptive thresholds
    private var energyHistory = RunningStats(windowSize: 100)
    private var pitchHistory = RunningStats(windowSize: 50)
    private var rateHistory = RunningStats(windowSize: 30)
    
    // Temporal tracking
    private var recentFeatures: [ProsodicFeatures] = []
    private var previousEmotion: EmotionalState = EmotionalState()
    private var previousLabel: EmotionLabel = .neutral
    private var lastEmitTime: TimeInterval = 0
    private var silenceStartTime: TimeInterval?
    private var speechFrameCount: Int = 0
    private var silenceFrameCount: Int = 0
    private var currentTime: TimeInterval = 0
    
    // Pitch tracking state
    private var lastPitch: Float = 0
    private var pitchBuffer: [Float] = []  // Recent pitch values for contour
    
    // Smoothed output
    private var smoothedState = EmotionalState()
    
    // Pre-allocated FFT buffers
    private var fftSetup: vDSP_DFT_Setup?
    private var fftRealBuffer: [Float]
    private var fftImagBuffer: [Float]
    
    // MARK: - Init
    
    init(config: Config = Config()) {
        self.config = config
        self.fftRealBuffer = [Float](repeating: 0, count: config.frameSize)
        self.fftImagBuffer = [Float](repeating: 0, count: config.frameSize)
        self.fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(config.frameSize), .FORWARD)
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    // MARK: - Public API
    
    /// Feed audio samples continuously. Processes in real-time.
    func process(samples: [Float], timestamp: TimeInterval) {
        analysisQueue.async { [weak self] in
            self?.processInternal(samples: samples, timestamp: timestamp)
        }
    }
    
    /// Reset all state (new session)
    func reset() {
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameBuffer.removeAll()
            self.recentFeatures.removeAll()
            self.pitchBuffer.removeAll()
            self.energyHistory = RunningStats(windowSize: 100)
            self.pitchHistory = RunningStats(windowSize: 50)
            self.rateHistory = RunningStats(windowSize: 30)
            self.previousEmotion = EmotionalState()
            self.previousLabel = .neutral
            self.smoothedState = EmotionalState()
            self.lastEmitTime = 0
            self.silenceStartTime = nil
            self.speechFrameCount = 0
            self.silenceFrameCount = 0
            self.lastPitch = 0
        }
    }
    
    // MARK: - Internal Processing
    
    private func processInternal(samples: [Float], timestamp: TimeInterval) {
        currentTime = timestamp
        frameBuffer.append(samples)
        
        // Process in overlapping frames (frameSize=480, hop=160)
        while frameBuffer.count >= config.frameSize {
            let frame = frameBuffer.consumeFrameCopy(count: config.frameSize, advance: config.hopSize)
            
            let features = extractFeatures(frame: frame, timestamp: timestamp)
            recentFeatures.append(features)
            
            // Keep last ~5 seconds of features
            let maxFeatures = Int(5.0 / (Double(config.hopSize) / Double(config.sampleRate)))
            if recentFeatures.count > maxFeatures {
                recentFeatures.removeFirst(recentFeatures.count - maxFeatures)
            }
        }
        
        // Emit sentiment at configured interval
        if timestamp - lastEmitTime >= config.emitInterval {
            let emotion = computeEmotion()
            
            // Smooth output
            smoothedState.valence = lerp(smoothedState.valence, emotion.valence, t: 1 - config.smoothingFactor)
            smoothedState.arousal = lerp(smoothedState.arousal, emotion.arousal, t: 1 - config.smoothingFactor)
            smoothedState.dominance = lerp(smoothedState.dominance, emotion.dominance, t: 1 - config.smoothingFactor)
            smoothedState.confidence = emotion.confidence
            
            // Detect shift
            let newLabel = smoothedState.label
            if newLabel != previousLabel && smoothedState.confidence > 0.4 {
                onSentimentShift?(previousLabel, newLabel)
                previousLabel = newLabel
            }
            
            let latestFeatures = recentFeatures.last ?? ProsodicFeatures()
            onSentimentUpdate?(smoothedState, latestFeatures)
            
            previousEmotion = smoothedState
            lastEmitTime = timestamp
        }
    }
    
    // MARK: - Feature Extraction
    
    private func extractFeatures(frame: [Float], timestamp: TimeInterval) -> ProsodicFeatures {
        var features = ProsodicFeatures()
        features.timestamp = timestamp
        
        let n = frame.count
        
        // 1. RMS Energy
        var sumSq: Float = 0
        vDSP_svesq(frame, 1, &sumSq, vDSP_Length(n))
        let rms = sqrt(sumSq / Float(n))
        features.rmsEnergy = rms
        features.isSpeech = rms > config.energyFloor
        
        energyHistory.add(rms)
        
        // Energy delta (relative to recent average)
        if energyHistory.count > 5 {
            features.energyDelta = (rms - energyHistory.mean) / max(energyHistory.stdDev, 0.001)
        }
        
        // Track speech/silence
        if features.isSpeech {
            speechFrameCount += 1
            if silenceStartTime != nil {
                let pauseLen = Float(timestamp - (silenceStartTime ?? timestamp))
                features.pauseDuration = pauseLen
                silenceStartTime = nil
            }
            silenceFrameCount = 0
        } else {
            silenceFrameCount += 1
            if silenceStartTime == nil {
                silenceStartTime = timestamp
            }
            features.pauseDuration = Float(timestamp - (silenceStartTime ?? timestamp))
            speechFrameCount = 0
        }
        
        guard features.isSpeech else { return features }
        
        // 2. Pitch Detection (YIN-inspired autocorrelation)
        let (pitch, pitchConf) = detectPitch(frame: frame)
        if pitchConf > config.pitchConfidenceThreshold {
            features.pitchHz = pitch
            features.pitchDelta = pitch - lastPitch
            lastPitch = pitch
            
            pitchHistory.add(pitch)
            pitchBuffer.append(pitch)
            if pitchBuffer.count > 20 { pitchBuffer.removeFirst() }
            
            features.pitchVariability = pitchHistory.stdDev
            features.pitchContour = detectContour()
        }
        
        // 3. Spectral Features
        let (tilt, centroid) = computeSpectralFeatures(frame: frame)
        features.spectralTilt = tilt
        features.spectralCentroid = centroid
        
        // 4. Speech Rate (via energy envelope peaks = syllable nuclei)
        features.speechRate = estimateSpeechRate()
        
        // 5. Harmonic-to-Noise Ratio (simplified)
        features.harmonicToNoise = estimateHNR(frame: frame, pitch: pitch)
        
        // 6. Jitter (pitch perturbation)
        if pitchBuffer.count >= 3 {
            features.jitter = computeJitter()
        }
        
        // 7. Pause frequency
        features.pauseFrequency = estimatePauseFrequency()
        
        return features
    }
    
    // MARK: - Pitch Detection (Simplified YIN)
    
    private func detectPitch(frame: [Float]) -> (hz: Float, confidence: Float) {
        let n = frame.count
        let minLag = Int(config.sampleRate / config.maxPitch)
        let maxLag = min(n / 2, Int(config.sampleRate / config.minPitch))
        
        guard maxLag > minLag else { return (0, 0) }
        
        // Difference function
        var diffFunc = [Float](repeating: 0, count: maxLag - minLag)
        
        for tau in minLag..<maxLag {
            var sum: Float = 0
            for j in 0..<(n - tau) {
                let diff = frame[j] - frame[j + tau]
                sum += diff * diff
            }
            diffFunc[tau - minLag] = sum
        }
        
        // Cumulative mean normalized difference
        var cmndf = [Float](repeating: 1.0, count: diffFunc.count)
        var runningSum: Float = 0
        
        for i in 0..<diffFunc.count {
            runningSum += diffFunc[i]
            if runningSum > 0 {
                cmndf[i] = diffFunc[i] * Float(i + 1) / runningSum
            }
        }
        
        // Find first dip below threshold
        let threshold: Float = 0.15
        var bestLag = minLag
        var bestVal: Float = 1.0
        
        for i in 1..<cmndf.count {
            if cmndf[i] < threshold {
                bestLag = i + minLag
                bestVal = cmndf[i]
                break
            }
            if cmndf[i] < bestVal {
                bestVal = cmndf[i]
                bestLag = i + minLag
            }
        }
        
        let hz = config.sampleRate / Float(bestLag)
        let confidence = 1.0 - min(bestVal, 1.0)
        
        // Sanity check
        guard hz >= config.minPitch && hz <= config.maxPitch else {
            return (0, 0)
        }
        
        return (hz, confidence)
    }
    
    // MARK: - Pitch Contour Detection
    
    private func detectContour() -> PitchContour {
        guard pitchBuffer.count >= 5 else { return .flat }
        
        let recent = Array(pitchBuffer.suffix(8))
        let n = recent.count
        let half = n / 2
        
        let firstHalf = Array(recent.prefix(half))
        let secondHalf = Array(recent.suffix(half))
        
        let firstMean = firstHalf.reduce(0, +) / Float(firstHalf.count)
        let secondMean = secondHalf.reduce(0, +) / Float(secondHalf.count)
        
        let delta = secondMean - firstMean
        let range = (recent.max() ?? 0) - (recent.min() ?? 0)
        
        // Relative to speaker's pitch range
        let normalizedDelta = delta / max(pitchHistory.stdDev * 2, 10)
        
        if normalizedDelta > 0.5 { return .rising }
        if normalizedDelta < -0.5 { return .falling }
        
        // Check for peak or dip
        let midIdx = n / 2
        let midVal = recent[midIdx]
        if midVal > firstMean && midVal > secondMean && range > pitchHistory.stdDev {
            return .peaked
        }
        if midVal < firstMean && midVal < secondMean && range > pitchHistory.stdDev {
            return .dipped
        }
        
        return .flat
    }
    
    // MARK: - Spectral Features
    
    private func computeSpectralFeatures(frame: [Float]) -> (tilt: Float, centroid: Float) {
        let n = frame.count
        
        // Apply Hanning window
        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))
        
        // Compute magnitude spectrum via DFT
        var realPart = windowed
        var imagPart = [Float](repeating: 0, count: n)
        
        if let setup = fftSetup {
            var outReal = [Float](repeating: 0, count: n)
            var outImag = [Float](repeating: 0, count: n)
            vDSP_DFT_Execute(setup, &realPart, &imagPart, &outReal, &outImag)
            
            // Magnitude spectrum (first half only — Nyquist)
            let halfN = n / 2
            var magnitudes = [Float](repeating: 0, count: halfN)
            
            for i in 0..<halfN {
                magnitudes[i] = sqrt(outReal[i] * outReal[i] + outImag[i] * outImag[i])
            }
            
            // Spectral tilt: ratio of high-frequency to low-frequency energy
            let midBin = halfN / 2
            let lowEnergy = magnitudes[1..<midBin].reduce(0, +)
            let highEnergy = magnitudes[midBin..<halfN].reduce(0, +)
            let totalEnergy = lowEnergy + highEnergy
            let tilt: Float = totalEnergy > 0 ? highEnergy / totalEnergy : 0.5
            
            // Spectral centroid
            var weightedSum: Float = 0
            var sumMag: Float = 0
            for i in 1..<halfN {
                let freq = Float(i) * config.sampleRate / Float(n)
                weightedSum += freq * magnitudes[i]
                sumMag += magnitudes[i]
            }
            let centroid = sumMag > 0 ? weightedSum / sumMag : 0
            
            return (tilt, centroid)
        }
        
        return (0.5, 1000)
    }
    
    // MARK: - Speech Rate Estimation
    
    private func estimateSpeechRate() -> Float {
        // Count energy peaks in recent features (~syllable nuclei)
        let recent = recentFeatures.suffix(50)  // ~500ms
        guard recent.count > 5 else { return 0 }
        
        let energies = recent.map { $0.rmsEnergy }
        let mean = energies.reduce(0, +) / Float(energies.count)
        
        var peaks = 0
        for i in 1..<(energies.count - 1) {
            if energies[i] > energies[i-1] && energies[i] > energies[i+1] && energies[i] > mean {
                peaks += 1
            }
        }
        
        // Convert to syllables/second
        let windowDuration = Double(recent.count) * Double(config.hopSize) / Double(config.sampleRate)
        let rate = Float(peaks) / Float(windowDuration)
        
        return min(rate, 10.0)  // Cap at 10 syl/s
    }
    
    // MARK: - HNR Estimation
    
    private func estimateHNR(frame: [Float], pitch: Float) -> Float {
        guard pitch > 0 else { return 0 }
        
        let period = Int(config.sampleRate / pitch)
        guard period > 0 && period * 2 < frame.count else { return 0 }
        
        // Compare adjacent periods
        var harmonicEnergy: Float = 0
        var noiseEnergy: Float = 0
        
        for i in 0..<period {
            let mean = (frame[i] + frame[i + period]) / 2.0
            let diff = frame[i] - frame[i + period]
            harmonicEnergy += mean * mean
            noiseEnergy += diff * diff
        }
        
        guard noiseEnergy > 0 else { return 20 }  // Very clean
        let hnr = 10 * log10(harmonicEnergy / noiseEnergy)
        return max(-10, min(30, hnr))
    }
    
    // MARK: - Jitter
    
    private func computeJitter() -> Float {
        guard pitchBuffer.count >= 3 else { return 0 }
        
        let recent = Array(pitchBuffer.suffix(10))
        var perturbationSum: Float = 0
        
        for i in 1..<recent.count {
            perturbationSum += abs(recent[i] - recent[i-1])
        }
        
        let meanPitch = recent.reduce(0, +) / Float(recent.count)
        guard meanPitch > 0 else { return 0 }
        
        let jitter = (perturbationSum / Float(recent.count - 1)) / meanPitch
        return jitter
    }
    
    // MARK: - Pause Frequency
    
    private func estimatePauseFrequency() -> Float {
        let recent = recentFeatures.suffix(100)
        guard recent.count > 10 else { return 0 }
        
        var pauses = 0
        var wasSpeech = false
        
        for f in recent {
            if f.isSpeech && !wasSpeech {
                // Speech resumed after silence = a pause just ended
                if wasSpeech == false && pauses > 0 { /* already counting */ }
            }
            if !f.isSpeech && wasSpeech {
                pauses += 1
            }
            wasSpeech = f.isSpeech
        }
        
        let windowDuration = Double(recent.count) * Double(config.hopSize) / Double(config.sampleRate)
        return Float(pauses) / Float(windowDuration) * 60.0  // per minute
    }
    
    // MARK: - Emotion Computation
    
    private func computeEmotion() -> EmotionalState {
        guard !recentFeatures.isEmpty else {
            return EmotionalState()
        }
        
        let speechFeatures = recentFeatures.filter { $0.isSpeech }
        guard !speechFeatures.isEmpty else {
            return EmotionalState(confidence: 0.1)
        }
        
        let avgEnergy = speechFeatures.map(\.rmsEnergy).reduce(0, +) / Float(speechFeatures.count)
        let avgPitch = speechFeatures.compactMap { $0.pitchHz > 0 ? $0.pitchHz : nil }
        let avgPitchHz = avgPitch.isEmpty ? 0 : avgPitch.reduce(0, +) / Float(avgPitch.count)
        let avgTilt = speechFeatures.map(\.spectralTilt).reduce(0, +) / Float(speechFeatures.count)
        let avgRate = speechFeatures.map(\.speechRate).reduce(0, +) / Float(speechFeatures.count)
        let avgJitter = speechFeatures.compactMap { $0.jitter > 0 ? $0.jitter : nil }
        let jitterVal = avgJitter.isEmpty ? 0 : avgJitter.reduce(0, +) / Float(avgJitter.count)
        let avgHNR = speechFeatures.compactMap { $0.harmonicToNoise != 0 ? $0.harmonicToNoise : nil }
        let hnrVal = avgHNR.isEmpty ? 10 : avgHNR.reduce(0, +) / Float(avgHNR.count)
        
        // Recent contours
        let risingCount = speechFeatures.filter { $0.pitchContour == .rising }.count
        let fallingCount = speechFeatures.filter { $0.pitchContour == .falling }.count
        let contourRatio = Float(risingCount) / max(Float(risingCount + fallingCount), 1.0)
        
        // Pause info
        let recentPauses = speechFeatures.filter { $0.pauseDuration > 0.3 }.count
        
        // --- Map features to emotional dimensions ---
        
        // VALENCE (positive ↔ negative)
        // Positive: higher pitch range, falling contours (assertions), clean HNR
        // Negative: high jitter (tense), rising contours (uncertain), spectral tension
        var valence: Float = 0
        valence += normalize(pitchHistory.stdDev, low: 5, high: 40) * 0.3     // Pitch variety → positive
        valence -= normalize(jitterVal, low: 0, high: 0.05) * 0.3             // Jitter → negative
        valence += normalize(hnrVal, low: 5, high: 25) * 0.2                  // Clean voice → positive
        valence -= (contourRatio - 0.5) * 0.4                                  // Rising → uncertainty
        valence = clamp(valence, -1, 1)
        
        // AROUSAL (excited ↔ calm)
        // High: loud, fast, high pitch, high spectral energy
        // Low: quiet, slow, low pitch
        var arousal: Float = 0
        arousal += normalize(avgEnergy, low: energyHistory.mean * 0.5, high: energyHistory.mean * 2.0) * 0.3
        arousal += normalize(avgRate, low: 2, high: 6) * 0.3
        arousal += normalize(avgTilt, low: 0.2, high: 0.5) * 0.2
        if avgPitchHz > 0 {
            arousal += normalize(avgPitchHz, low: pitchHistory.mean * 0.8, high: pitchHistory.mean * 1.3) * 0.2
        }
        arousal = clamp(arousal * 2 - 1, -1, 1)  // Center around 0
        
        // DOMINANCE (confident ↔ hesitant)
        // Confident: steady pitch, few pauses, falling contours, strong energy
        // Hesitant: many pauses, pitch instability, low energy, rising contours
        var dominance: Float = 0
        dominance += (1.0 - normalize(jitterVal, low: 0, high: 0.04)) * 0.25   // Low jitter → confident
        dominance -= normalize(Float(recentPauses), low: 0, high: 5) * 0.25     // Many pauses → hesitant
        dominance -= contourRatio * 0.25                                          // Rising → uncertain
        dominance += normalize(avgEnergy, low: energyHistory.mean * 0.5, high: energyHistory.mean * 1.5) * 0.25
        dominance = clamp(dominance * 2 - 0.5, -1, 1)
        
        // Confidence based on amount of speech data
        let speechRatio = Float(speechFeatures.count) / Float(recentFeatures.count)
        let confidence = min(1.0, speechRatio * 1.5) * (avgPitchHz > 0 ? 1.0 : 0.5)
        
        return EmotionalState(
            valence: valence,
            arousal: arousal,
            dominance: dominance,
            confidence: confidence
        )
    }
    
    // MARK: - Math Helpers
    
    private func normalize(_ value: Float, low: Float, high: Float) -> Float {
        guard high > low else { return 0.5 }
        return clamp((value - low) / (high - low), 0, 1)
    }
    
    private func clamp(_ value: Float, _ low: Float, _ high: Float) -> Float {
        min(high, max(low, value))
    }
    
    private func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }
}

// MARK: - Running Statistics

/// Efficient online computation of mean and standard deviation
/// using Welford's algorithm with a sliding window.
struct RunningStats {
    private var values: [Float] = []
    private let windowSize: Int
    private(set) var mean: Float = 0
    private(set) var variance: Float = 0
    private(set) var count: Int = 0
    
    init(windowSize: Int) {
        self.windowSize = windowSize
        self.values.reserveCapacity(windowSize)
    }
    
    var stdDev: Float { sqrt(max(0, variance)) }
    
    mutating func add(_ value: Float) {
        values.append(value)
        if values.count > windowSize {
            values.removeFirst()
        }
        count = values.count
        
        // Recompute (for windowed, just recalc)
        let sum = values.reduce(0, +)
        mean = sum / Float(count)
        
        let sumSq = values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
        variance = count > 1 ? sumSq / Float(count - 1) : 0
    }
}
