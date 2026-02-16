import Foundation

/// Swift wrapper around whisper.cpp for local speech-to-text transcription.
/// Runs entirely on-device using Metal GPU acceleration on Apple Silicon.
final class WhisperTranscriber {
    
    // MARK: - Configuration
    
    struct Config {
        var modelPath: String
        var language: String = "fr"       // "fr", "en", "auto" for auto-detect
        var translate: Bool = false        // translate to English
        var threads: Int = 4              // CPU threads (for non-Metal fallback)
        var speedUp: Bool = false         // 2x speed at lower quality
        var maxTokensPerSegment: Int = 64
        var temperature: Float = 0.0      // 0 = greedy decoding (fastest)
        var noContext: Bool = true         // don't use previous context (better for streaming)
    }
    
    // MARK: - Properties
    
    private var context: OpaquePointer?  // whisper_context*
    private let config: Config
    private let transcribeQueue = DispatchQueue(label: "com.voicescribe.whisper", qos: .userInteractive)
    private var isLoaded = false
    
    // MARK: - Init
    
    init(config: Config) {
        self.config = config
    }
    
    deinit {
        unloadModel()
    }
    
    // MARK: - Model Management
    
    /// Load the Whisper model into memory. Call once at startup.
    func loadModel() throws {
        guard !isLoaded else { return }
        
        guard FileManager.default.fileExists(atPath: config.modelPath) else {
            throw WhisperError.modelNotFound(config.modelPath)
        }
        
        Log.transcription.info("Loading Whisper model: \(self.config.modelPath)")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Initialize with default params (Metal is auto-detected)
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true  // Use Metal on Apple Silicon
        
        context = whisper_init_from_file_with_params(config.modelPath, cparams)
        
        guard context != nil else {
            throw WhisperError.modelLoadFailed
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Log.transcription.info("Whisper model loaded in \(String(format: "%.1f", elapsed))s")
        isLoaded = true
    }
    
    func unloadModel() {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
            isLoaded = false
            Log.transcription.info("Whisper model unloaded")
        }
    }
    
    // MARK: - Transcription
    
    /// Transcribe a chunk of audio samples.
    /// - Parameters:
    ///   - samples: PCM Float32 audio at 16kHz mono
    ///   - chunkTime: timestamp of this chunk in the session
    ///   - completion: called with transcription results
    func transcribe(
        samples: [Float],
        chunkTime: TimeInterval,
        completion: @escaping (Result<[TranscriptionSegment], Error>) -> Void
    ) {
        guard let ctx = context else {
            completion(.failure(WhisperError.modelNotLoaded))
            return
        }
        
        guard !samples.isEmpty else {
            completion(.success([]))
            return
        }
        
        transcribeQueue.async { [config] in
            // Configure whisper parameters
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            
            let lang = config.language
            lang.withCString { langPtr in
                params.language = langPtr
                params.translate = config.translate
                params.n_threads = Int32(config.threads)
                params.no_context = config.noContext
                params.temperature = config.temperature
                params.max_tokens = Int32(config.maxTokensPerSegment)
                params.print_progress = false
                params.print_timestamps = false
                params.print_realtime = false
                params.print_special = false
                params.suppress_blank = true
                params.suppress_nst = true // suppress non-speech tokens
                
                // Run inference
                let startTime = CFAbsoluteTimeGetCurrent()
                
                let result = samples.withUnsafeBufferPointer { bufferPtr in
                    whisper_full(ctx, params, bufferPtr.baseAddress, Int32(samples.count))
                }
                
                let inferenceTime = CFAbsoluteTimeGetCurrent() - startTime
                
                guard result == 0 else {
                    completion(.failure(WhisperError.transcriptionFailed))
                    return
                }
                
                // Check audio energy — skip if silence
                let rms = sqrtf(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
                if rms < 0.003 {
                    completion(.success([]))
                    return
                }

                // Extract segments
                let numSegments = whisper_full_n_segments(ctx)
                var segments: [TranscriptionSegment] = []

                for i in 0..<numSegments {
                    guard let textPtr = whisper_full_get_segment_text(ctx, i) else { continue }
                    let text = String(cString: textPtr).trimmingCharacters(in: .whitespacesAndNewlines)

                    // Skip empty or noise-only segments
                    if text.isEmpty || text == "[BLANK_AUDIO]" || text.starts(with: "[") { continue }

                    // Skip known Whisper hallucinations during silence
                    if Self.isHallucination(text) { continue }
                    
                    let segStart = TimeInterval(whisper_full_get_segment_t0(ctx, i)) / 100.0
                    let segEnd = TimeInterval(whisper_full_get_segment_t1(ctx, i)) / 100.0
                    
                    let segment = TranscriptionSegment(
                        text: text,
                        startTime: chunkTime + segStart,
                        endTime: chunkTime + segEnd,
                        speaker: .me,  // Phase 1: mic only = always "me"
                        confidence: 1.0
                    )
                    segments.append(segment)
                }
                
                let audioSeconds = Double(samples.count) / 16000.0
                let rtf = inferenceTime / audioSeconds
                Log.transcription.debug("\(numSegments) segments in \(String(format: "%.2f", inferenceTime))s (RTF: \(String(format: "%.2f", rtf))x)")
                
                completion(.success(segments))
            }
        }
    }
    
    /// Synchronous version for simpler usage
    func transcribeSync(samples: [Float], chunkTime: TimeInterval) throws -> [TranscriptionSegment] {
        var result: Result<[TranscriptionSegment], Error>?
        let semaphore = DispatchSemaphore(value: 0)
        
        transcribe(samples: samples, chunkTime: chunkTime) {
            result = $0
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result! {
        case .success(let segments): return segments
        case .failure(let error): throw error
        }
    }
    
    // MARK: - Hallucination Filter

    private static let hallucinationPatterns: Set<String> = [
        "sous-titrage société radio-canada",
        "sous-titres réalisés para la communauté d'amara.org",
        "sous-titres par la communauté d'amara.org",
        "sous-titrage st 501",
        "merci d'avoir regardé",
        "merci de votre attention",
        "s'abonner",
        "je vous remercie",
    ]

    private static let shortHallucinations: Set<String> = [
        "merci.", "...", "…", "you", "thank you.", "thanks.",
        "bye.", "the end.", "fin.", "merci",
    ]

    private static func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased()
        if shortHallucinations.contains(lower) { return true }
        for pattern in hallucinationPatterns {
            if lower.contains(pattern) { return true }
        }
        // Repeated single words/phrases (e.g. "Merci. Merci. Merci.")
        let words = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let unique = Set(words)
            if unique.count == 1 { return true }
        }
        return false
    }

    // MARK: - Error Types
    
    enum WhisperError: LocalizedError {
        case modelNotFound(String)
        case modelLoadFailed
        case modelNotLoaded
        case transcriptionFailed
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "Modèle Whisper introuvable: \(path). Lancez setup.sh d'abord."
            case .modelLoadFailed:
                return "Échec du chargement du modèle Whisper. Fichier corrompu ?"
            case .modelNotLoaded:
                return "Le modèle Whisper n'est pas chargé. Appelez loadModel() d'abord."
            case .transcriptionFailed:
                return "La transcription a échoué."
            }
        }
    }
}
