import Foundation

/// Analyzes transcribed text for commercial signals invisible to prosody.
///
/// Key insight: prosody tells HOW they feel, text tells WHAT they say.
/// A calm "non merci, on a déjà un prestataire" is prosodically neutral
/// but commercially devastating. This analyzer catches that.
///
/// Design:
/// - Pattern-based with negation awareness (not NLP/ML — runs in <1ms)
/// - French-primary with English fallback
/// - Returns a TextSignal that HybridSentiment merges with prosodic data
/// - Detects: objections, buying signals, hesitation, engagement, authority markers
///
/// Example outputs:
///   "C'est trop cher"          → Objection(.price, strength: 0.8)
///   "Ça m'intéresse beaucoup"  → BuyingSignal(.interest, strength: 0.7)
///   "On verra..."              → Hesitation(strength: 0.5)
///   "Je dois en parler à..."   → AuthorityFlag
///   "Combien ça coûte ?"       → BuyingSignal(.pricing_inquiry, strength: 0.6)
final class TextSignalAnalyzer {
    
    // MARK: - Output Types
    
    struct TextSignal {
        /// Overall commercial valence from text (-1 = strong objection, +1 = strong buying signal)
        let commercialValence: Float
        
        /// Detected signals (can be multiple per utterance)
        let signals: [DetectedSignal]
        
        /// Negation detected in the text (modifies interpretation)
        let hasNegation: Bool
        
        /// Whether this text meaningfully affects sentiment (vs "oui oui" filler)
        let isSignificant: Bool
        
        /// Confidence in the analysis
        let confidence: Float
    }
    
    struct DetectedSignal {
        let type: SignalType
        let category: SignalCategory
        let strength: Float         // 0.0 to 1.0
        let matchedPattern: String  // What triggered it
        let textExcerpt: String     // Context around the match
    }
    
    enum SignalType {
        case objection
        case buyingSignal
        case hesitation
        case engagement
        case disengagement
        case authorityFlag    // "je dois en parler à mon directeur"
        case urgencySignal    // "on a besoin de ça pour la semaine prochaine"
        case competitorMention
    }
    
    enum SignalCategory: String {
        // Objection categories
        case price = "Prix"
        case timing = "Timing"
        case competitor = "Concurrent"
        case authority = "Décisionnaire"
        case needDenial = "Pas de besoin"
        case trustIssue = "Confiance"
        case generic = "Générique"
        
        // Buying signal categories
        case interest = "Intérêt"
        case pricingInquiry = "Demande prix"
        case implementation = "Mise en place"
        case timeline = "Calendrier"
        case agreement = "Accord"
        case elaboration = "Élaboration"
        
        // Other
        case hedging = "Couverture"
        case filler = "Remplissage"
    }
    
    // MARK: - Pattern Definitions
    
    /// Each pattern has: regex/keywords, signal type, category, base strength, negation-sensitive
    private struct Pattern {
        let keywords: [String]         // Any of these must be present
        let antiKeywords: [String]     // If any of these present, don't match
        let type: SignalType
        let category: SignalCategory
        let baseStrength: Float
        let negationFlips: Bool        // If negation found, flip the signal
        let requiresWholeWord: Bool    // "pas" vs "passerelle"
    }
    
    private let patterns: [Pattern]
    
    // MARK: - Negation Detection
    
    /// French negation particles and patterns
    private let negationPatterns: [String] = [
        "ne ", "n'", " pas ", " plus ", " jamais ", " aucun", " rien ",
        " ni ", " non ", "pas de ", "pas du ", "pas le ", "pas la ",
        "pas les ", "pas un", "pas encore", "pas vraiment", "pas sûr",
        "pas certain", "sans "
    ]
    
    /// Words that LOOK like negation but aren't in context
    private let falseNegations: [String] = [
        "pas mal", "pas du tout mal", "pourquoi pas", "n'est-ce pas",
        "pas que", "n'hésitez pas"
    ]
    
    // MARK: - Init
    
    init() {
        self.patterns = Self.buildPatterns()
    }
    
    // MARK: - Analysis
    
    /// Analyze a text segment for commercial signals.
    /// Call after each Whisper transcription result.
    func analyze(text: String, speaker: Speaker = .other) -> TextSignal {
        let normalized = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr"))
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip very short or empty text
        guard trimmed.count > 3 else {
            return TextSignal(commercialValence: 0, signals: [], hasNegation: false,
                              isSignificant: false, confidence: 0)
        }
        
        // Detect negation
        let negation = detectNegation(in: normalized)
        
        // Match patterns
        var detectedSignals: [DetectedSignal] = []
        
        for pattern in patterns {
            if let match = matchPattern(pattern, in: normalized, negated: negation.isNegated) {
                detectedSignals.append(match)
            }
        }
        
        // Check for questions (engagement signal)
        if normalized.contains("?") || isQuestionForm(normalized) {
            let qSignal = DetectedSignal(
                type: .engagement,
                category: .elaboration,
                strength: 0.3,
                matchedPattern: "question",
                textExcerpt: String(trimmed.prefix(60))
            )
            detectedSignals.append(qSignal)
        }
        
        // Check for elaborate responses (engagement signal)
        let wordCount = trimmed.split(separator: " ").count
        if speaker == .other && wordCount > 20 {
            let eSignal = DetectedSignal(
                type: .engagement,
                category: .elaboration,
                strength: min(0.6, Float(wordCount) / 50.0),
                matchedPattern: "réponse élaborée (\(wordCount) mots)",
                textExcerpt: String(trimmed.prefix(60))
            )
            detectedSignals.append(eSignal)
        }
        
        // Compute overall commercial valence
        let valence = computeCommercialValence(signals: detectedSignals)
        let isSignificant = detectedSignals.contains { $0.strength > 0.3 }
        let confidence = detectedSignals.isEmpty ? 0.1 : min(0.9, Float(detectedSignals.count) * 0.25 + 0.3)
        
        return TextSignal(
            commercialValence: valence,
            signals: detectedSignals,
            hasNegation: negation.isNegated,
            isSignificant: isSignificant,
            confidence: confidence
        )
    }
    
    // MARK: - Negation Detection
    
    private struct NegationResult {
        let isNegated: Bool
        let positions: [Range<String.Index>]
    }
    
    private func detectNegation(in text: String) -> NegationResult {
        // Check for false negations first
        for fp in falseNegations {
            if text.contains(fp) {
                // Remove the false negation from consideration
                let cleaned = text.replacingOccurrences(of: fp, with: "")
                // Check if there's STILL negation in the rest
                let stillNegated = negationPatterns.contains { cleaned.contains($0) }
                if !stillNegated {
                    return NegationResult(isNegated: false, positions: [])
                }
            }
        }
        
        // Standard negation detection
        var positions: [Range<String.Index>] = []
        for pattern in negationPatterns {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: pattern, range: searchRange) {
                positions.append(range)
                searchRange = range.upperBound..<text.endIndex
            }
        }
        
        return NegationResult(isNegated: !positions.isEmpty, positions: positions)
    }
    
    // MARK: - Pattern Matching
    
    private func matchPattern(_ pattern: Pattern, in text: String, negated: Bool) -> DetectedSignal? {
        // Check anti-keywords first
        for anti in pattern.antiKeywords {
            if text.contains(anti) { return nil }
        }
        
        // Find matching keyword
        var matchedKeyword: String? = nil
        for keyword in pattern.keywords {
            if pattern.requiresWholeWord {
                // Word boundary check (spaces or start/end)
                let padded = " \(text) "
                if padded.contains(" \(keyword) ") || padded.contains(" \(keyword),") ||
                   padded.contains(" \(keyword).") || padded.contains(" \(keyword)?") {
                    matchedKeyword = keyword
                    break
                }
            } else {
                if text.contains(keyword) {
                    matchedKeyword = keyword
                    break
                }
            }
        }
        
        guard let matched = matchedKeyword else { return nil }
        
        // Handle negation flipping
        var finalType = pattern.type
        var finalStrength = pattern.baseStrength
        var finalCategory = pattern.category
        
        if negated && pattern.negationFlips {
            // "Je n'ai PAS de budget" → objection (not buying signal)
            // "Ce n'est PAS intéressant" → objection (not engagement)
            switch pattern.type {
            case .buyingSignal:
                finalType = .objection
                finalCategory = .generic
                finalStrength = pattern.baseStrength * 0.7
            case .engagement:
                finalType = .disengagement
                finalStrength = pattern.baseStrength * 0.6
            case .objection:
                // Double negation or "ce n'est pas un problème" = positive
                finalType = .buyingSignal
                finalCategory = .agreement
                finalStrength = pattern.baseStrength * 0.5
            default:
                break
            }
        }
        
        // Extract context around match
        let excerpt: String
        if let range = text.range(of: matched) {
            let start = text.index(range.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex
            excerpt = String(text[start..<end])
        } else {
            excerpt = String(text.prefix(60))
        }
        
        return DetectedSignal(
            type: finalType,
            category: finalCategory,
            strength: finalStrength,
            matchedPattern: matched,
            textExcerpt: excerpt
        )
    }
    
    // MARK: - Question Detection
    
    private func isQuestionForm(_ text: String) -> Bool {
        let questionStarters = [
            "est-ce que", "qu'est-ce", "comment", "pourquoi", "quand",
            "combien", "quel", "quelle", "quels", "quelles", "ou est",
            "qui est", "y a-t-il", "avez-vous", "pouvez-vous",
            "pensez-vous", "croyez-vous", "seriez-vous"
        ]
        return questionStarters.contains { text.hasPrefix($0) || text.contains(" \($0) ") }
    }
    
    // MARK: - Commercial Valence Computation
    
    private func computeCommercialValence(signals: [DetectedSignal]) -> Float {
        guard !signals.isEmpty else { return 0 }
        
        var totalWeighted: Float = 0
        var totalWeight: Float = 0
        
        for signal in signals {
            let sign: Float
            switch signal.type {
            case .buyingSignal, .engagement, .urgencySignal:
                sign = 1.0
            case .objection, .disengagement:
                sign = -1.0
            case .hesitation, .authorityFlag:
                sign = -0.3
            case .competitorMention:
                sign = -0.5
            }
            
            let weight = signal.strength
            totalWeighted += sign * weight
            totalWeight += weight
        }
        
        return totalWeight > 0 ? max(-1, min(1, totalWeighted / totalWeight)) : 0
    }
    
    // MARK: - Pattern Definitions
    
    private static func buildPatterns() -> [Pattern] {
        var patterns: [Pattern] = []
        
        // ═══════════════════════════════════════
        // OBJECTIONS
        // ═══════════════════════════════════════
        
        // Price objections
        patterns.append(Pattern(
            keywords: ["trop cher", "trop couteux", "hors budget", "depasse notre budget",
                       "on n'a pas le budget", "pas les moyens", "c'est cher",
                       "budgetairement", "financierement"],
            antiKeywords: ["pas trop cher", "pas si cher"],
            type: .objection, category: .price,
            baseStrength: 0.8, negationFlips: false, requiresWholeWord: false
        ))
        
        // Timing objections
        patterns.append(Pattern(
            keywords: ["pas le moment", "pas le bon moment", "pas maintenant",
                       "l'annee prochaine", "dans quelques mois", "on verra plus tard",
                       "on reviendra vers vous", "rappelez-moi dans", "pas prioritaire",
                       "pas urgent", "pas d'urgence"],
            antiKeywords: [],
            type: .objection, category: .timing,
            baseStrength: 0.7, negationFlips: false, requiresWholeWord: false
        ))
        
        // Competitor / existing solution
        patterns.append(Pattern(
            keywords: ["deja un prestataire", "deja equipe", "deja une solution",
                       "on utilise deja", "on travaille deja avec", "satisfait de notre",
                       "on a deja", "on est deja engage", "sous contrat"],
            antiKeywords: [],
            type: .objection, category: .competitor,
            baseStrength: 0.8, negationFlips: false, requiresWholeWord: false
        ))
        
        // Authority / decision
        patterns.append(Pattern(
            keywords: ["faut que j'en parle", "dois en parler", "pas le decideur",
                       "mon directeur", "ma direction", "le comite", "valider en interne",
                       "pas seul a decider", "hierarchie", "c'est pas moi qui decide"],
            antiKeywords: [],
            type: .authorityFlag, category: .authority,
            baseStrength: 0.6, negationFlips: false, requiresWholeWord: false
        ))
        
        // Need denial
        patterns.append(Pattern(
            keywords: ["pas interesse", "pas besoin", "ca ne nous concerne pas",
                       "on n'a pas ce probleme", "ca va bien comme ca",
                       "pas pour nous", "ca ne correspond pas",
                       "pas concerne", "pas notre sujet"],
            antiKeywords: [],
            type: .objection, category: .needDenial,
            baseStrength: 0.9, negationFlips: false, requiresWholeWord: false
        ))
        
        // Trust / credibility
        patterns.append(Pattern(
            keywords: ["je ne vous connais pas", "c'est trop beau", "ca parait trop",
                       "des preuves", "des references", "qui utilise", "j'ai des doutes",
                       "sceptique", "mefiant"],
            antiKeywords: [],
            type: .objection, category: .trustIssue,
            baseStrength: 0.6, negationFlips: false, requiresWholeWord: false
        ))
        
        // Generic soft objection
        patterns.append(Pattern(
            keywords: ["non merci", "ca ira", "merci mais", "je decline",
                       "on va passer", "sans suite", "laissez tomber"],
            antiKeywords: [],
            type: .objection, category: .generic,
            baseStrength: 0.7, negationFlips: false, requiresWholeWord: false
        ))
        
        // ═══════════════════════════════════════
        // BUYING SIGNALS
        // ═══════════════════════════════════════
        
        // Direct interest
        patterns.append(Pattern(
            keywords: ["ca m'interesse", "c'est interessant", "je suis interesse",
                       "ca nous interesse", "dites-m'en plus", "j'aimerais en savoir",
                       "parlez-moi de", "racontez-moi", "expliquez-moi",
                       "je veux en savoir plus"],
            antiKeywords: ["pas vraiment", "pas tellement"],
            type: .buyingSignal, category: .interest,
            baseStrength: 0.6, negationFlips: true, requiresWholeWord: false
        ))
        
        // Pricing inquiry (strong buying signal!)
        patterns.append(Pattern(
            keywords: ["combien ca coute", "quel est le prix", "quel est le tarif",
                       "c'est combien", "votre tarif", "vos tarifs", "grille tarifaire",
                       "un devis", "une proposition", "proposition commerciale",
                       "offre commerciale", "conditions commerciales"],
            antiKeywords: [],
            type: .buyingSignal, category: .pricingInquiry,
            baseStrength: 0.8, negationFlips: true, requiresWholeWord: false
        ))
        
        // Implementation questions (very strong!)
        patterns.append(Pattern(
            keywords: ["comment on fait pour", "comment ca se passe",
                       "les etapes", "le deploiement", "la mise en place",
                       "combien de temps pour", "l'implementation", "le setup",
                       "l'installation", "la migration", "l'integration",
                       "on commence comment", "pour demarrer"],
            antiKeywords: [],
            type: .buyingSignal, category: .implementation,
            baseStrength: 0.7, negationFlips: true, requiresWholeWord: false
        ))
        
        // Timeline commitment
        patterns.append(Pattern(
            keywords: ["on pourrait commencer", "on demarre quand",
                       "disponible quand", "a partir de quand", "cette semaine",
                       "ce mois-ci", "rapidement", "le plus tot possible",
                       "des lundi", "des demain", "des que possible"],
            antiKeywords: [],
            type: .buyingSignal, category: .timeline,
            baseStrength: 0.8, negationFlips: true, requiresWholeWord: false
        ))
        
        // Agreement / validation
        patterns.append(Pattern(
            keywords: ["exactement", "c'est exactement", "tout a fait",
                       "absolument", "vous avez raison", "c'est ca",
                       "effectivement", "je suis d'accord", "on est d'accord",
                       "bien vu", "c'est vrai"],
            antiKeywords: ["pas exactement", "pas tout a fait", "pas d'accord"],
            type: .buyingSignal, category: .agreement,
            baseStrength: 0.5, negationFlips: true, requiresWholeWord: false
        ))
        
        // Urgency from prospect
        patterns.append(Pattern(
            keywords: ["on a besoin", "c'est urgent", "il nous faut",
                       "on perd du temps", "on ne peut plus", "probleme critique",
                       "ca nous coute", "on doit resoudre", "deadline"],
            antiKeywords: ["pas besoin", "pas urgent"],
            type: .urgencySignal, category: .timeline,
            baseStrength: 0.8, negationFlips: true, requiresWholeWord: false
        ))
        
        // ═══════════════════════════════════════
        // HESITATION
        // ═══════════════════════════════════════
        
        patterns.append(Pattern(
            keywords: ["peut-etre", "je ne sais pas", "on verra",
                       "il faudrait que", "il faudrait voir", "eventuellement",
                       "a voir", "je reflechis", "laissez-moi reflechir",
                       "faut que j'y pense", "je suis pas sur", "pas certain"],
            antiKeywords: [],
            type: .hesitation, category: .hedging,
            baseStrength: 0.5, negationFlips: false, requiresWholeWord: false
        ))
        
        // Competitor mention (not objection per se, but commercial intelligence)
        patterns.append(Pattern(
            keywords: ["salesforce", "hubspot", "pipedrive", "zoho",
                       "votre concurrent", "un concurrent", "d'autres solutions",
                       "on compare", "on benchmark", "en appel d'offre"],
            antiKeywords: [],
            type: .competitorMention, category: .competitor,
            baseStrength: 0.5, negationFlips: false, requiresWholeWord: false
        ))
        
        return patterns
    }
}
