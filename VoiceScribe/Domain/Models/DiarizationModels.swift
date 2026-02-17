import Foundation

// MARK: - Speaker Profile (Entity)

/// A recognized speaker in the conversation.
/// The embedding vector allows re-identification across audio chunks.
struct SpeakerProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var embedding: [Float]
    var segmentCount: Int
    var totalSpeakingTime: TimeInterval

    init(label: String, embedding: [Float] = []) {
        self.id = UUID()
        self.label = label
        self.embedding = embedding
        self.segmentCount = 0
        self.totalSpeakingTime = 0
    }

    /// Reconstitute from persistence.
    init(id: UUID, label: String, embedding: [Float], segmentCount: Int, totalSpeakingTime: TimeInterval) {
        self.id = id
        self.label = label
        self.embedding = embedding
        self.segmentCount = segmentCount
        self.totalSpeakingTime = totalSpeakingTime
    }

    // Hashable by id only (embeddings change)
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SpeakerProfile, rhs: SpeakerProfile) -> Bool { lhs.id == rhs.id }

    /// Cosine similarity between two speaker embeddings.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dotProduct / denom : 0
    }

    mutating func recordSegment(duration: TimeInterval) {
        segmentCount += 1
        totalSpeakingTime += duration
    }
}

// MARK: - Diarization Segment (Value Object)

/// Who spoke when, with confidence.
struct DiarizationSegment: Identifiable {
    let id: UUID
    let speakerProfile: SpeakerProfile
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float

    var duration: TimeInterval { endTime - startTime }

    init(speaker: SpeakerProfile, startTime: TimeInterval, endTime: TimeInterval, confidence: Float = 1.0) {
        self.id = UUID()
        self.speakerProfile = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

// MARK: - Diarization Result (Value Object)

/// Aggregated result of diarization analysis on an audio chunk.
struct DiarizationResult {
    let segments: [DiarizationSegment]
    let activeSpeakers: [SpeakerProfile]

    var speakerCount: Int { activeSpeakers.count }
    var isEmpty: Bool { segments.isEmpty }

    static let empty = DiarizationResult(segments: [], activeSpeakers: [])
}

// MARK: - Speaker Balance (Value Object)

/// Speaking time balance across all identified speakers.
struct SpeakerBalance {
    let speakerTimes: [UUID: TimeInterval]
    let totalTime: TimeInterval

    func ratio(for speakerId: UUID) -> Double {
        guard totalTime > 0, let time = speakerTimes[speakerId] else { return 0 }
        return time / totalTime
    }

    var dominantSpeaker: UUID? {
        speakerTimes.max(by: { $0.value < $1.value })?.key
    }

    var isBalanced: Bool {
        guard speakerTimes.count >= 2, totalTime > 0 else { return true }
        let ratios = speakerTimes.values.map { $0 / totalTime }
        let maxRatio = ratios.max() ?? 0
        return maxRatio < 0.75 // No speaker dominates >75%
    }

    static let empty = SpeakerBalance(speakerTimes: [:], totalTime: 0)
}
