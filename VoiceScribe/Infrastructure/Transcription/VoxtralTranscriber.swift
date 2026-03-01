import Foundation

/// Holds a single `vox_ctx_t*` loaded once. Two `VoxtralTranscriber` instances
/// share one context to avoid doubling the ~10.8 GB memory footprint.
/// All access is serialized through a dedicated dispatch queue.
final class VoxtralContext {
    private(set) var ctx: OpaquePointer?  // vox_ctx_t*
    let queue = DispatchQueue(label: "com.voicescribe.voxtral", qos: .userInteractive)

    /// Load the Voxtral model from `modelDir`.
    func load(modelDir: String, delayMs: Int32 = 480) throws {
        guard ctx == nil else { return }
        Log.transcription.info("Loading Voxtral model from: \(modelDir)")
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let c = vox_load(modelDir) else {
            throw VoxtralError.modelLoadFailed
        }
        vox_set_delay(c, delayMs)
        ctx = c

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Log.transcription.info("Voxtral model loaded in \(String(format: "%.1f", elapsed))s")
    }

    func unload() {
        if let c = ctx {
            vox_free(c)
            ctx = nil
            Log.transcription.info("Voxtral model unloaded")
        }
    }

    deinit { unload() }
}

/// Voxtral-based transcriber, drop-in replacement for `WhisperTranscriber`.
/// Operates in batch mode: VAD feeds speech chunks, Voxtral transcribes them.
final class VoxtralTranscriber {

    struct Config {
        var modelDir: String
        var language: String = "fr"
        var delayMs: Int32 = 480
    }

    private let config: Config
    private let sharedContext: VoxtralContext
    private var isLoaded = false

    init(config: Config, sharedContext: VoxtralContext) {
        self.config = config
        self.sharedContext = sharedContext
    }

    deinit { unloadModel() }

    // MARK: - Model Management

    func loadModel() throws {
        guard !isLoaded else { return }
        try sharedContext.load(modelDir: config.modelDir, delayMs: config.delayMs)
        isLoaded = true
    }

    func unloadModel() {
        guard isLoaded else { return }
        isLoaded = false
        // Context is shared — only freed when VoxtralContext itself is deallocated
    }

    // MARK: - Transcription

    func transcribe(
        samples: [Float],
        chunkTime: TimeInterval,
        completion: @escaping (Result<[TranscriptionSegment], Error>) -> Void
    ) {
        guard let ctx = sharedContext.ctx else {
            completion(.failure(VoxtralError.modelNotLoaded))
            return
        }

        guard !samples.isEmpty else {
            completion(.success([]))
            return
        }

        sharedContext.queue.async {
            // Check audio energy — skip silence
            let rms = sqrtf(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
            if rms < 0.003 {
                completion(.success([]))
                return
            }

            let startTime = CFAbsoluteTimeGetCurrent()

            // Init stream, feed samples, finish
            guard let stream = vox_stream_init(ctx) else {
                completion(.failure(VoxtralError.transcriptionFailed))
                return
            }

            samples.withUnsafeBufferPointer { buf in
                vox_stream_feed(stream, buf.baseAddress, Int32(samples.count))
            }
            vox_stream_finish(stream)

            // Collect all output tokens
            let maxTokens: Int32 = 4096
            let tokenBuf = UnsafeMutablePointer<CChar>.allocate(capacity: Int(maxTokens))
            defer { tokenBuf.deallocate() }

            var fullText = ""
            while true {
                let got = vox_stream_get(stream, tokenBuf, maxTokens)
                if got <= 0 { break }
                tokenBuf[Int(got)] = 0  // null-terminate
                fullText += String(cString: tokenBuf)
            }

            vox_stream_free(stream)

            let inferenceTime = CFAbsoluteTimeGetCurrent() - startTime

            // Clean up the text
            let text = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty, !HallucinationFilter.isHallucination(text) else {
                completion(.success([]))
                return
            }

            let audioSeconds = Double(samples.count) / 16000.0
            let rtf = inferenceTime / audioSeconds
            Log.transcription.debug("Voxtral: \(String(format: "%.2f", inferenceTime))s (RTF: \(String(format: "%.2f", rtf))x)")

            let segment = TranscriptionSegment(
                text: text,
                startTime: chunkTime,
                endTime: chunkTime + audioSeconds,
                speaker: .me,
                confidence: 1.0
            )
            completion(.success([segment]))
        }
    }

    // MARK: - Errors

    enum VoxtralError: LocalizedError {
        case modelNotFound(String)
        case modelLoadFailed
        case modelNotLoaded
        case transcriptionFailed

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "Modèle Voxtral introuvable: \(path). Lancez setup.sh voxtral d'abord."
            case .modelLoadFailed:
                return "Échec du chargement du modèle Voxtral."
            case .modelNotLoaded:
                return "Le modèle Voxtral n'est pas chargé."
            case .transcriptionFailed:
                return "La transcription Voxtral a échoué."
            }
        }
    }
}
