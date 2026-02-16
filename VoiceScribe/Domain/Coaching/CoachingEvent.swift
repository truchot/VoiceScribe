import Foundation

// MARK: - Coaching Domain Events
//
// Explicit events emitted by domain objects when meaningful state changes occur.
// Replaces implicit state diffing (Set comparisons, string equality checks)
// with declarative "something happened" signals.
//
// Emitters:
//   - MovementDetector  → .movementChanged
//   - ConversationMemory → .slotCaptured
//   - Coordinator        → .alertDetected (from sentiment pipeline)
//
// Subscribers:
//   - CoachingPersistenceUseCase (persists to SQLite)
//   - Future: analytics, real-time notifications, CRM sync...

enum CoachingEvent {

    /// Movement switched (auto-detected or manual override).
    case movementChanged(
        from: ConversationMovement,
        to: ConversationMovement,
        elapsed: TimeInterval,
        isManualOverride: Bool
    )

    /// A memory slot was captured or updated.
    case slotCaptured(
        slot: ConversationMemory.CapturedSlot,
        previousValue: String?,
        isNewSlot: Bool
    )

    /// A commercial alert was detected (objection, buying signal, etc.).
    case alertDetected(
        alert: CommercialAlert,
        elapsed: TimeInterval
    )
}

// MARK: - Event Bus

/// Synchronous, in-process event bus for coaching domain events.
///
/// Designed for simplicity over scalability:
/// - Synchronous dispatch (subscribers run on caller's thread)
/// - No backpressure, no queuing
/// - Subscribers persist across reset() — they're wired once at init
///
/// This is appropriate for a single-process macOS app where all
/// events originate from the main actor's coaching pipeline.
final class CoachingEventBus {

    typealias Handler = (CoachingEvent) -> Void

    private var handlers: [Handler] = []

    /// Register a subscriber. Called once during setup, not per-session.
    func subscribe(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    /// Emit an event to all subscribers.
    func emit(_ event: CoachingEvent) {
        for handler in handlers {
            handler(event)
        }
    }
}
