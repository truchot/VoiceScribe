import Foundation

/// Live memory of the conversation.
///
/// As the prospect speaks, the memory captures key information (memory slots)
/// and makes it available to the coaching engine for personalized suggestions.
///
/// Example flow:
///   Univers: captures "company_size: 30 personnes"
///   Enjeux: captures "main_pain: perte de temps sur les devis"
///   Profondeur: captures "pain_cost_time: 2 jours par semaine"
///   Proposition: coach says "Pour votre équipe de 30 personnes qui perd 2j/sem
///                sur les devis, voici comment on résout ça..."
///
/// The memory also tracks what's MISSING, so the coach can nudge:
///   "Vous n'avez pas encore abordé le budget. Pensez-y avant de présenter."
final class ConversationMemory {
    
    // MARK: - Stored Data
    
    /// All captured slots: key → value
    private(set) var slots: [String: CapturedSlot] = [:]
    
    /// Cache of high-confidence slot keys for O(1) skip in extract()
    private var filledHighConfidence: Set<String> = []
    
    /// Timeline of captures (for post-call report)
    private(set) var captureHistory: [CaptureEvent] = []
    
    /// Manual overrides from the user
    private(set) var overrides: [String: String] = [:]
    
    // Domain events
    var eventBus: CoachingEventBus?
    
    // MARK: - Types
    
    struct CapturedSlot {
        let key: String
        let value: String
        let movement: ConversationMovement  // Where it was captured
        let confidence: Float               // How confident the detection is
        let timestamp: TimeInterval
        let source: CaptureSource
    }
    
    enum CaptureSource: String {
        case autoDetected = "Auto"      // Keyword matching
        case manualEntry = "Manuel"     // User typed it
        case llmExtracted = "LLM"      // Local LLM extraction (future)
    }
    
    struct CaptureEvent {
        let slot: CapturedSlot
        let previousValue: String?
        let timestamp: TimeInterval
    }
    
    // MARK: - Public API
    
    /// Try to extract memory slots from a transcript segment.
    /// Returns newly filled slots.
    @discardableResult
    func extract(
        from segment: TranscriptionSegment,
        currentMovement: ConversationMovement,
        elapsed: TimeInterval
    ) -> [CapturedSlot] {
        
        let blueprint = ConversationFramework.blueprint(for: currentMovement)
        let text = segment.text.lowercased()
        var newCaptures: [CapturedSlot] = []
        
        for slot in blueprint.memorySlots {
            // Skip if already filled with high confidence (O(1) set lookup)
            if filledHighConfidence.contains(slot.key) { continue }
            
            // Check hints
            for hint in slot.detectionHints {
                if text.contains(hint) {
                    // Try to extract the actual value (not just detect presence)
                    let value = extractValue(for: slot.key, from: segment.text, hint: hint)
                    
                    let captured = CapturedSlot(
                        key: slot.key,
                        value: value,
                        movement: currentMovement,
                        confidence: CoachingThresholds.memoryKeywordConfidence,
                        timestamp: elapsed,
                        source: .autoDetected
                    )
                    
                    let prev = slots[slot.key]?.value
                    let isNew = prev == nil
                    slots[slot.key] = captured
                    if captured.confidence > CoachingThresholds.memoryHighConfidence {
                        filledHighConfidence.insert(slot.key)
                    }
                    captureHistory.append(CaptureEvent(slot: captured, previousValue: prev, timestamp: elapsed))
                    newCaptures.append(captured)
                    eventBus?.emit(.slotCaptured(slot: captured, previousValue: prev, isNewSlot: isNew))
                    break  // One capture per slot per segment
                }
            }
        }
        
        // Also check slots from ALL movements (some info appears early)
        for movement in ConversationMovement.allCases where movement != currentMovement {
            let bp = ConversationFramework.blueprint(for: movement)
            for slot in bp.memorySlots {
                if filledHighConfidence.contains(slot.key) || slots[slot.key] != nil { continue }
                for hint in slot.detectionHints {
                    if text.contains(hint) {
                        let value = extractValue(for: slot.key, from: segment.text, hint: hint)
                        let captured = CapturedSlot(
                            key: slot.key, value: value,
                            movement: movement, confidence: CoachingThresholds.memoryCrossMovementConfidence,
                            timestamp: elapsed, source: .autoDetected
                        )
                        slots[slot.key] = captured
                        captureHistory.append(CaptureEvent(slot: captured, previousValue: nil, timestamp: elapsed))
                        newCaptures.append(captured)
                        eventBus?.emit(.slotCaptured(slot: captured, previousValue: nil, isNewSlot: true))
                        break
                    }
                }
            }
        }
        
        return newCaptures
    }
    
    /// Manually set a memory slot (user override)
    func set(key: String, value: String, movement: ConversationMovement, elapsed: TimeInterval) {
        let captured = CapturedSlot(
            key: key, value: value,
            movement: movement, confidence: 1.0,
            timestamp: elapsed, source: .manualEntry
        )
        let prev = slots[key]?.value
        let isNew = prev == nil
        slots[key] = captured
        filledHighConfidence.insert(key)  // Manual = confidence 1.0 → always cached
        overrides[key] = value
        captureHistory.append(CaptureEvent(slot: captured, previousValue: prev, timestamp: elapsed))
        eventBus?.emit(.slotCaptured(slot: captured, previousValue: prev, isNewSlot: isNew))
    }
    
    /// Get a slot value
    func get(_ key: String) -> String? {
        slots[key]?.value
    }
    
    /// Check if a slot is filled
    func has(_ key: String) -> Bool {
        slots[key] != nil
    }
    
    /// Get all missing critical slots for a movement
    func missingCriticalSlots(for movement: ConversationMovement) -> [MemorySlot] {
        let blueprint = ConversationFramework.blueprint(for: movement)
        return blueprint.memorySlots.filter { slot in
            slot.importance == .critical && !has(slot.key)
        }
    }
    
    /// Get all missing slots up to (and including) a movement
    func missingSlotsBefore(_ movement: ConversationMovement) -> [MemorySlot] {
        var missing: [MemorySlot] = []
        for m in ConversationMovement.allCases {
            if m.rawValue > movement.rawValue { break }
            let bp = ConversationFramework.blueprint(for: m)
            for slot in bp.memorySlots {
                if (slot.importance == .critical || slot.importance == .important) && !has(slot.key) {
                    missing.append(slot)
                }
            }
        }
        return missing
    }
    
    /// Build a context string for coaching suggestions
    /// Uses captured info to personalize advice
    func contextString() -> String {
        var parts: [String] = []
        
        if let name = get("prospect_name") { parts.append("Prospect: \(name)") }
        if let company = get("company_name") { parts.append("Entreprise: \(company)") }
        if let size = get("company_size") { parts.append("Taille: \(size)") }
        if let pain = get("main_pain") { parts.append("Douleur: \(pain)") }
        if let cost = get("pain_cost_time") { parts.append("Coût temps: \(cost)") }
        if let costMoney = get("pain_cost_money") { parts.append("Coût €: \(costMoney)") }
        if let outcome = get("desired_outcome") { parts.append("Objectif: \(outcome)") }
        if let budget = get("budget_range") { parts.append("Budget: \(budget)") }
        if let timeline = get("timeline") { parts.append("Timeline: \(timeline)") }
        if let decider = get("decision_maker") { parts.append("Décideur: \(decider)") }
        
        return parts.joined(separator: " | ")
    }
    
    /// Generate personalized phrase by substituting memory placeholders
    /// e.g. "Votre problème de [main_pain] coûte [pain_cost_time]"
    /// → "Votre problème de devis qui traînent coûte 2 jours par semaine"
    func personalize(_ template: String) -> String {
        var result = template
        for (key, slot) in slots {
            result = result.replacingOccurrences(of: "[\(key)]", with: slot.value)
        }
        // Remove unfilled placeholders
        result = result.replacingOccurrences(of: #"\[[a-z_]+\]"#, with: "[...]", options: .regularExpression)
        return result
    }
    
    /// Readiness score for a movement: 0.0 (not ready) to 1.0 (all info available)
    func readiness(for movement: ConversationMovement) -> Float {
        let bp = ConversationFramework.blueprint(for: movement)
        let criticalSlots = bp.memorySlots.filter { $0.importance == .critical }
        guard !criticalSlots.isEmpty else { return 1.0 }
        let filled = criticalSlots.filter { has($0.key) }.count
        return Float(filled) / Float(criticalSlots.count)
    }
    
    /// Reset all memory
    func reset() {
        slots.removeAll()
        filledHighConfidence.removeAll()
        captureHistory.removeAll()
        overrides.removeAll()
    }
    
    // MARK: - Post-Call Report
    
    func generateReport() -> CallReport {
        CallReport(
            slotsCollected: slots,
            captureTimeline: captureHistory,
            missingCritical: missingSlotsBefore(.suivi),
            qualificationScore: qualificationScore(),
            discoveryScore: discoveryScore()
        )
    }
    
    struct CallReport {
        let slotsCollected: [String: CapturedSlot]
        let captureTimeline: [CaptureEvent]
        let missingCritical: [MemorySlot]
        let qualificationScore: Float  // 0-1: BANT completion
        let discoveryScore: Float      // 0-1: Pain/Impact/Vision completion
    }
    
    private func qualificationScore() -> Float {
        let keys = ["budget_range", "decision_maker", "timeline", "decision_process"]
        let filled = keys.filter { has($0) }.count
        return Float(filled) / Float(keys.count)
    }
    
    private func discoveryScore() -> Float {
        let keys = ["main_pain", "pain_trigger", "pain_cost_time", "desired_outcome", "success_criteria"]
        let filled = keys.filter { has($0) }.count
        return Float(filled) / Float(keys.count)
    }
    
    // MARK: - Value Extraction
    
    /// Try to extract meaningful value around a hint keyword.
    /// Simple extraction — enhanced by LLM in future.
    private func extractValue(for key: String, from text: String, hint: String) -> String {
        // For now, extract the sentence containing the hint
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?;"))
        for sentence in sentences {
            if sentence.lowercased().contains(hint) {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return String(trimmed.prefix(200))
                }
            }
        }
        return "✓ (mentionné)"
    }
}
