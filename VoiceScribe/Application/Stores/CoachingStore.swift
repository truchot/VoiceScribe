import Foundation

/// Focused observable for coaching state.
///
/// Holds the current coaching output, movement, and coaching toggle.
/// Views showing transcription text or audio levels don't re-render
/// when coaching advice changes.
@MainActor
final class CoachingStore: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var coachingOutput: ConversationCoach.CoachingOutput?
    @Published private(set) var currentMovement: ConversationMovement = .accueil
    @Published var coachingEnabled = true
    
    // MARK: - Coach Engine Reference (set by coordinator)
    
    /// The underlying coach — exposed for memory access and report generation.
    /// Not @Published because it doesn't change (the output does).
    private(set) var coach: CoachingProvider?
    
    // MARK: - Updates (called from coordinator)
    
    func configure(coach: CoachingProvider) {
        self.coach = coach
    }
    
    func updateAdvice(_ output: ConversationCoach.CoachingOutput) {
        coachingOutput = output
        currentMovement = output.movement
    }
    
    func reset() {
        coachingOutput = nil
        currentMovement = .accueil
        coach?.reset()
    }
    
    // MARK: - User Actions (commands: UI → Coordinator)
    //
    // Architecture: Two communication patterns coexist BY DESIGN:
    //   - CoachingEventBus: domain events flow OUTWARD (domain → persistence, analytics)
    //   - Closures below:  user commands flow INWARD (UI → coordinator → coach)
    //
    // Closures are the right tool for commands because:
    //   1. Commands need the coordinator's context (elapsed time from RecordingStore)
    //   2. Commands are targeted (one handler), not broadcast (many subscribers)
    //   3. Some return values (generateReport returns PostCallReport?)
    
    var onOverrideMovement: ((ConversationMovement) -> Void)?
    var onSetMemorySlot: ((String, String) -> Void)?
    var onGenerateReport: (() -> PostCallReport?)?
    var onExportReport: (() -> Void)?
    
    func overrideMovement(_ movement: ConversationMovement) {
        onOverrideMovement?(movement)
    }
    
    func setMemorySlot(key: String, value: String) {
        onSetMemorySlot?(key, value)
    }
    
    func generateReport() -> PostCallReport? {
        onGenerateReport?()
    }
    
    func exportReport() {
        onExportReport?()
    }
}
