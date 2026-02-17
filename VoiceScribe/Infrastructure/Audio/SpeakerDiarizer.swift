import Foundation
import Accelerate

/// Embedding-based speaker diarization using audio spectral features.
///
/// Extracts speaker embeddings from audio chunks and clusters them to identify
/// distinct speakers. Uses MFCC-like spectral features as a lightweight
/// alternative to neural speaker embeddings, suitable for real-time use.
///
/// Thread safety: all mutable state is protected by `stateQueue`.
///
/// Pipeline:
/// ```
/// Audio -> Frame -> FFT -> Mel bands -> Embedding -> Cosine similarity -> Cluster
/// ```
final class SpeakerDiarizer: DiarizationProvider {

    // MARK: - Configuration

    struct Config {
        var identityThreshold: Float = 0.85
        var maxSpeakers: Int = 8
        var minSpeechEnergy: Float = 0.01
        var embeddingAverageWindow: Int = 3
    }

    static let embeddingDimension = 32

    // MARK: - Protocol Callbacks

    var onSpeakerChange: ((_ speaker: SpeakerProfile) -> Void)?

    // MARK: - State (protected by stateQueue)

    private var config: Config
    private var speakers: [SpeakerProfile] = []
    private var currentSpeakerIndex: Int?
    private var speakerTimes: [UUID: TimeInterval] = [:]
    private var totalTime: TimeInterval = 0
    private var lastTimestamp: TimeInterval = 0
    private var recentEmbeddings: [[Float]] = []

    /// Serializes all mutable state access.
    private let stateQueue = DispatchQueue(label: "com.voicescribe.diarizer.state")

    // MARK: - FFT Setup (created once, reused across calls)

    private let fftSetup: FFTSetup?
    private let fftLog2n: vDSP_Length
    private let fftFrameSize = 512

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
        // Pre-compute FFT setup once (expensive to create per-call)
        let log2n = vDSP_Length(log2(Float(fftFrameSize)))
        self.fftLog2n = log2n
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - DiarizationProvider

    func process(samples: [Float], timestamp: TimeInterval) {
        guard isSpeech(samples) else { return }

        let embedding = extractEmbedding(from: samples)
        guard embedding.contains(where: { $0 != 0 }) else { return }

        stateQueue.sync {
            // Average recent embeddings for stability
            recentEmbeddings.append(embedding)
            if recentEmbeddings.count > config.embeddingAverageWindow {
                recentEmbeddings.removeFirst()
            }
            let averaged = averageEmbeddings(recentEmbeddings)

            let (bestIndex, bestSimilarity) = findBestMatch(averaged)

            let duration = timestamp > lastTimestamp ? timestamp - lastTimestamp : 0
            lastTimestamp = timestamp

            if let bestIndex, bestSimilarity >= config.identityThreshold {
                speakers[bestIndex].recordSegment(duration: duration)
                speakerTimes[speakers[bestIndex].id, default: 0] += duration
                totalTime += duration

                if currentSpeakerIndex != bestIndex {
                    currentSpeakerIndex = bestIndex
                    let speaker = speakers[bestIndex]
                    stateQueue.async { [weak self] in
                        self?.onSpeakerChange?(speaker)
                    }
                }
            } else if speakers.count < config.maxSpeakers {
                var newSpeaker = SpeakerProfile(
                    label: "Participant \(speakers.count + 1)",
                    embedding: averaged
                )
                newSpeaker.recordSegment(duration: duration)
                speakerTimes[newSpeaker.id] = duration
                totalTime += duration
                speakers.append(newSpeaker)
                currentSpeakerIndex = speakers.count - 1
                let speaker = newSpeaker
                stateQueue.async { [weak self] in
                    self?.onSpeakerChange?(speaker)
                }
            }
        }
    }

    func identifySpeaker(from samples: [Float]) -> SpeakerProfile? {
        guard isSpeech(samples) else { return nil }
        let embedding = extractEmbedding(from: samples)
        guard embedding.contains(where: { $0 != 0 }) else { return nil }

        return stateQueue.sync {
            let (bestIndex, bestSimilarity) = findBestMatch(embedding)
            guard let bestIndex, bestSimilarity >= config.identityThreshold else { return nil }
            return speakers[bestIndex]
        }
    }

    func currentSpeakers() -> [SpeakerProfile] {
        stateQueue.sync { speakers }
    }

    func speakerBalance() -> SpeakerBalance {
        stateQueue.sync { SpeakerBalance(speakerTimes: speakerTimes, totalTime: totalTime) }
    }

    func reset() {
        stateQueue.sync {
            speakers.removeAll()
            currentSpeakerIndex = nil
            speakerTimes.removeAll()
            totalTime = 0
            lastTimestamp = 0
            recentEmbeddings.removeAll()
        }
    }

    // MARK: - Embedding Extraction

    func extractEmbedding(from samples: [Float]) -> [Float] {
        let frameSize = fftFrameSize
        let hopSize = 256
        let numMelBands = Self.embeddingDimension
        let sampleRate: Float = 16000

        guard samples.count >= frameSize else {
            return [Float](repeating: 0, count: numMelBands)
        }

        var melAccumulator = [Float](repeating: 0, count: numMelBands)
        var frameCount: Float = 0

        var i = 0
        while i + frameSize <= samples.count {
            // Use ArraySlice to avoid per-frame allocation
            let frameSlice = samples[i..<(i + frameSize)]

            let windowed = applyHannWindow(frameSlice)
            let magnitudes = fftMagnitude(windowed)
            let melEnergies = melFilterbank(magnitudes, numBands: numMelBands, sampleRate: sampleRate, fftSize: frameSize)

            for j in 0..<numMelBands {
                melAccumulator[j] += melEnergies[j]
            }
            frameCount += 1
            i += hopSize
        }

        guard frameCount > 0 else {
            return [Float](repeating: 0, count: numMelBands)
        }

        var embedding = melAccumulator.map { log(max($0 / frameCount, 1e-10)) }

        // L2 normalize
        var norm: Float = 0
        vDSP_svesq(embedding, 1, &norm, vDSP_Length(embedding.count))
        norm = sqrt(norm)
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }

        return embedding
    }

    // MARK: - Private Helpers

    private func isSpeech(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms > config.minSpeechEnergy
    }

    private func findBestMatch(_ embedding: [Float]) -> (Int?, Float) {
        var bestIndex: Int?
        var bestSimilarity: Float = -1

        for (idx, speaker) in speakers.enumerated() {
            let sim = SpeakerProfile.cosineSimilarity(embedding, speaker.embedding)
            if sim > bestSimilarity {
                bestSimilarity = sim
                bestIndex = idx
            }
        }

        return (bestIndex, bestSimilarity)
    }

    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        let dim = embeddings[0].count
        var avg = [Float](repeating: 0, count: dim)
        for emb in embeddings {
            for i in 0..<min(dim, emb.count) {
                avg[i] += emb[i]
            }
        }
        let n = Float(embeddings.count)
        return avg.map { $0 / n }
    }

    // MARK: - DSP Helpers

    private func applyHannWindow(_ frame: ArraySlice<Float>) -> [Float] {
        let n = frame.count
        return frame.enumerated().map { i, sample in
            let w = 0.5 * (1.0 - cos(2.0 * Float.pi * Float(i) / Float(n - 1)))
            return sample * w
        }
    }

    private func fftMagnitude(_ frame: [Float]) -> [Float] {
        let n = frame.count
        guard let fftSetup else {
            return [Float](repeating: 0, count: n / 2)
        }

        var realPart = [Float](repeating: 0, count: n / 2)
        var imagPart = [Float](repeating: 0, count: n / 2)
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

        frame.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(n / 2))
            }
        }

        vDSP_fft_zrip(fftSetup, &splitComplex, 1, fftLog2n, FFTDirection(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0, count: n / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))
        var sqrtMags = [Float](repeating: 0, count: n / 2)
        var count = Int32(n / 2)
        vvsqrtf(&sqrtMags, magnitudes, &count)

        return sqrtMags
    }

    private func melFilterbank(_ magnitudes: [Float], numBands: Int, sampleRate: Float, fftSize: Int) -> [Float] {
        let numBins = magnitudes.count
        let maxFreq = sampleRate / 2
        let minMel = hzToMel(0)
        let maxMel = hzToMel(maxFreq)

        let melPoints = (0...numBands + 1).map { i in
            minMel + Float(i) * (maxMel - minMel) / Float(numBands + 1)
        }
        let hzPoints = melPoints.map { melToHz($0) }
        let binPoints = hzPoints.map { Int(($0 / maxFreq) * Float(numBins - 1)) }

        var melEnergies = [Float](repeating: 0, count: numBands)

        for m in 0..<numBands {
            let startBin = binPoints[m]
            let centerBin = binPoints[m + 1]
            let endBin = binPoints[m + 2]

            for k in startBin..<centerBin where k < numBins {
                let weight = Float(k - startBin) / max(Float(centerBin - startBin), 1)
                melEnergies[m] += magnitudes[k] * weight
            }
            for k in centerBin..<endBin where k < numBins {
                let weight = Float(endBin - k) / max(Float(endBin - centerBin), 1)
                melEnergies[m] += magnitudes[k] * weight
            }
        }

        return melEnergies
    }

    private func hzToMel(_ hz: Float) -> Float {
        2595 * log10(1 + hz / 700)
    }

    private func melToHz(_ mel: Float) -> Float {
        700 * (pow(10, mel / 2595) - 1)
    }
}
