import Foundation

/// Merges prosodic analysis (HOW they sound) with text analysis (WHAT they say)
/// into an enriched EmotionalState.
///
/// The core insight:
/// ```
///   Prosody     Text              Result
///   ─────────   ───────────────   ──────────────────
///   Calm        "non merci"       → Disengaged (polite rejection)
///   Calm        "c'est combien?"  → Confident + interested
///   Animated    "c'est trop cher" → Frustrated (price objection)
///   Hesitant    "peut-être..."    → Hesitant (confirmed by both)
///   Enthused    "exactement!"     → Enthusiastic (confirmed)
///   Calm        "j'ai un budget"  → Confident + buying signal
/// ```
///
/// Rules:
/// 1. Text OVERRIDES prosody for objections (calm voice ≠ positive)
/// 2. Text AMPLIFIES prosody when both agree (enthusiastic voice + agreement)
/// 3. Text MODERATES prosody when they conflict (angry voice + "ça m'intéresse")
/// 4. Prosody wins when text is ambiguous (short "oui oui" filler)
final class HybridSentiment {
    
    // MARK: - Configuration
    
    struct Config {
        /// Weight of text signal vs prosody (0 = prosody only, 1 = text only)
        /// Default 0.4 = prosody-dominant but text has meaningful influence
        var textWeight: Float = 0.4
        
        /// Text overrides prosody entirely for strong signals above this threshold
        var textOverrideThreshold: Float = 0.75
        
        /// Below this text confidence, prosody is used alone
        var textMinConfidence: Float = 0.2
        
        /// Number of recent text signals to consider (sliding window)
        var textWindowSize: Int = 5
        
        /// Decay factor for older text signals (most recent = 1.0)
        var textDecayFactor: Float = 0.8
    }
    
    private let config: Config
    private let textAnalyzer = TextSignalAnalyzer()
    
    /// Rolling window of recent text signals
    private var recentTextSignals: [(signal: TextSignalAnalyzer.TextSignal, timestamp: TimeInterval)] = []
    
    /// Last significant text signal (for coaching)
    private(set) var lastSignificantSignal: TextSignalAnalyzer.TextSignal?
    private(set) var lastSignificantTimestamp: TimeInterval = 0
    
    // MARK: - Init
    
    init(config: Config = Config()) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Feed new transcribed text. Call after each Whisper segment.
    func feedText(_ text: String, speaker: Speaker, timestamp: TimeInterval) {
        let signal = textAnalyzer.analyze(text: text, speaker: speaker)
        
        recentTextSignals.append((signal: signal, timestamp: timestamp))
        
        // Trim window
        if recentTextSignals.count > config.textWindowSize * 2 {
            recentTextSignals = Array(recentTextSignals.suffix(config.textWindowSize))
        }
        
        if signal.isSignificant {
            lastSignificantSignal = signal
            lastSignificantTimestamp = timestamp
        }
    }
    
    /// Merge prosodic emotion with accumulated text signals and optional semantic analysis.
    /// Call each time SentimentStore would update (e.g. every 500ms).
    func merge(prosody: EmotionalState, at timestamp: TimeInterval) -> HybridResult {
        merge(prosody: prosody, semantic: nil, at: timestamp)
    }

    /// 3-channel merge: prosody + text patterns + semantic analysis.
    func merge(prosody: EmotionalState, semantic: SemanticAnalysis?, at timestamp: TimeInterval) -> HybridResult {
        let textAgg = aggregateTextSignals(at: timestamp)
        
        // If no significant text, return prosody with metadata
        guard textAgg.confidence >= config.textMinConfidence else {
            return HybridResult(
                emotion: prosody,
                textSignals: [],
                dominantSource: .prosody,
                commercialAlert: nil
            )
        }
        
        // Build merged emotion
        var merged = prosody
        let tw = effectiveTextWeight(textConfidence: textAgg.confidence, signalStrength: textAgg.maxStrength)
        let pw = 1.0 - tw
        
        // ── Rule 1: Strong text objection OVERRIDES prosodic valence ──
        if textAgg.maxStrength >= config.textOverrideThreshold &&
           textAgg.commercialValence < -0.3 {
            merged.valence = textAgg.commercialValence
            merged.dominance = min(prosody.dominance, -0.1) // Objection = not submissive, but negative
            // Boost confidence since we have strong signal
            merged.confidence = max(prosody.confidence, 0.7)
            
            return HybridResult(
                emotion: merged,
                textSignals: textAgg.signals,
                dominantSource: .textOverride,
                commercialAlert: buildAlert(signals: textAgg.signals, valence: textAgg.commercialValence)
            )
        }
        
        // ── Rule 2: Agreement = amplify ──
        let sameDirection = (prosody.valence > 0 && textAgg.commercialValence > 0) ||
                            (prosody.valence < 0 && textAgg.commercialValence < 0)
        
        if sameDirection {
            // Both agree → strengthen the signal
            merged.valence = prosody.valence * pw + textAgg.commercialValence * tw
            // Amplify slightly when both agree
            if abs(merged.valence) < abs(prosody.valence) + abs(textAgg.commercialValence) / 2 {
                merged.valence *= 1.15
            }
            merged.valence = max(-1, min(1, merged.valence))
            merged.confidence = min(1.0, prosody.confidence + 0.15)
            
            return HybridResult(
                emotion: merged,
                textSignals: textAgg.signals,
                dominantSource: .agreement,
                commercialAlert: buildAlert(signals: textAgg.signals, valence: textAgg.commercialValence)
            )
        }
        
        // ── Rule 3: Conflict = weighted merge ──
        merged.valence = prosody.valence * pw + textAgg.commercialValence * tw
        merged.valence = max(-1, min(1, merged.valence))
        
        // Text affects dominance for hesitation markers
        if textAgg.signals.contains(where: { $0.type == .hesitation }) {
            merged.dominance = min(prosody.dominance, prosody.dominance * pw + (-0.4) * tw)
        }
        
        // Buying signals boost dominance
        if textAgg.signals.contains(where: { $0.type == .buyingSignal }) {
            merged.dominance = max(prosody.dominance, prosody.dominance * pw + 0.3 * tw)
        }
        
        merged.confidence = max(prosody.confidence, textAgg.confidence)

        // ── Semantic enrichment (3rd channel) ──
        if let semantic, semantic.confidence > 0.3 {
            merged = enrichWithSemantic(merged, semantic: semantic)
        }

        return HybridResult(
            emotion: merged,
            textSignals: textAgg.signals,
            dominantSource: .blended,
            commercialAlert: textAgg.maxStrength > 0.5 ?
                buildAlert(signals: textAgg.signals, valence: textAgg.commercialValence) : nil
        )
    }

    /// Enrich a merged emotion with semantic text analysis.
    /// Semantic adjusts certainty→dominance and engagement→arousal.
    private func enrichWithSemantic(_ emotion: EmotionalState, semantic: SemanticAnalysis) -> EmotionalState {
        var enriched = emotion
        let sw: Float = 0.25 // Semantic weight (light touch — supplements rather than overrides)
        let pw: Float = 1.0 - sw

        // Semantic polarity contributes to valence
        enriched.valence = enriched.valence * pw + semantic.sentiment.polarity * sw
        enriched.valence = max(-1, min(1, enriched.valence))

        // Certainty maps to dominance
        let certDelta = (semantic.sentiment.certainty - 0.5) * 2.0 // -1..1 range
        enriched.dominance = enriched.dominance * pw + certDelta * 0.3 * sw
        enriched.dominance = max(-1, min(1, enriched.dominance))

        // Engagement maps to arousal
        let engDelta = (semantic.sentiment.engagement - 0.5) * 2.0
        enriched.arousal = enriched.arousal * pw + engDelta * 0.2 * sw
        enriched.arousal = max(-1, min(1, enriched.arousal))

        // Intent-based adjustments
        switch semantic.intent {
        case .objecting:
            enriched.valence = min(enriched.valence, enriched.valence - 0.1)
        case .committing:
            enriched.valence = max(enriched.valence, enriched.valence + 0.1)
            enriched.dominance = max(enriched.dominance, 0.2)
        case .deflecting:
            enriched.dominance = min(enriched.dominance, enriched.dominance - 0.1)
        default: break
        }

        enriched.confidence = min(1.0, enriched.confidence + semantic.confidence * 0.1)

        return enriched
    }
    
    /// Reset state (new session).
    func reset() {
        recentTextSignals.removeAll()
        lastSignificantSignal = nil
        lastSignificantTimestamp = 0
    }
    
    // MARK: - Result
    
    struct HybridResult {
        /// Merged emotional state (ready for SentimentStore)
        let emotion: EmotionalState
        
        /// Text signals that contributed (for coaching)
        let textSignals: [TextSignalAnalyzer.DetectedSignal]
        
        /// Which source dominated this result
        let dominantSource: Source
        
        /// Commercial alert (if strong text signal detected)
        let commercialAlert: CommercialAlert?
        
        enum Source {
            case prosody       // Text was insignificant
            case textOverride  // Text was strong objection/signal overriding prosody
            case agreement     // Both prosody and text aligned
            case blended       // Weighted combination
        }
    }
    
    // CommercialAlert is now a Domain type (Domain/Models/CommercialAlert.swift)
    
    // MARK: - Internal
    
    private struct AggregatedText {
        let commercialValence: Float
        let confidence: Float
        let maxStrength: Float
        let signals: [TextSignalAnalyzer.DetectedSignal]
    }
    
    private func aggregateTextSignals(at timestamp: TimeInterval) -> AggregatedText {
        // Get recent signals within the window
        let window = recentTextSignals.suffix(config.textWindowSize)
        guard !window.isEmpty else {
            return AggregatedText(commercialValence: 0, confidence: 0, maxStrength: 0, signals: [])
        }
        
        var weightedValence: Float = 0
        var totalWeight: Float = 0
        var allSignals: [TextSignalAnalyzer.DetectedSignal] = []
        var maxStrength: Float = 0
        var maxConfidence: Float = 0
        
        for (i, entry) in window.enumerated() {
            let recency = pow(config.textDecayFactor, Float(window.count - 1 - i))
            let weight = recency * entry.signal.confidence
            
            weightedValence += entry.signal.commercialValence * weight
            totalWeight += weight
            maxConfidence = max(maxConfidence, entry.signal.confidence)
            
            for signal in entry.signal.signals {
                allSignals.append(signal)
                maxStrength = max(maxStrength, signal.strength)
            }
        }
        
        let avgValence = totalWeight > 0 ? weightedValence / totalWeight : 0
        
        return AggregatedText(
            commercialValence: avgValence,
            confidence: maxConfidence,
            maxStrength: maxStrength,
            signals: allSignals
        )
    }
    
    private func effectiveTextWeight(textConfidence: Float, signalStrength: Float) -> Float {
        // Base weight from config
        var w = config.textWeight
        
        // Increase weight for strong signals
        if signalStrength > 0.7 { w += 0.15 }
        if signalStrength > 0.85 { w += 0.15 }
        
        // Scale by text confidence
        w *= textConfidence
        
        return max(0, min(0.8, w)) // Never let text completely dominate
    }
    
    private func buildAlert(
        signals: [TextSignalAnalyzer.DetectedSignal],
        valence: Float
    ) -> CommercialAlert? {
        // Find the strongest signal
        guard let strongest = signals.max(by: { $0.strength < $1.strength }) else { return nil }
        
        let type: CommercialAlert.AlertType
        let message: String
        
        switch strongest.type {
        case .objection:
            type = .objection
            message = "⚠️ Objection détectée : \(strongest.category.rawValue)"
        case .buyingSignal:
            type = .buyingSignal
            message = "✅ Signal d'achat : \(strongest.category.rawValue)"
        case .authorityFlag:
            type = .authority
            message = "👤 Pas le décisionnaire — identifier le circuit de décision"
        case .competitorMention:
            type = .competitor
            message = "🏢 Concurrent mentionné — différenciation nécessaire"
        case .urgencySignal:
            type = .buyingSignal
            message = "🔥 Urgence prospect — capitaliser maintenant"
        case .hesitation:
            type = .objection
            message = "🤔 Hésitation — rassurer ou creuser"
        case .engagement:
            type = .buyingSignal
            message = "💬 Engagement actif — bon momentum"
        case .disengagement:
            type = .objection
            message = "😶 Désengagement textuel — réengager"
        }
        
        return CommercialAlert(
            type: type,
            category: strongest.category.rawValue,
            message: message,
            strength: strongest.strength
        )
    }
}
