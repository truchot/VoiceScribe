import Foundation

/// Manages coaching data persistence via domain events + periodic polling.
///
/// Two persistence strategies:
/// 1. **Event-driven** (immediate): memory slots and commercial alerts
///    are persisted the moment they're captured, via CoachingEventBus.
///    No diffing needed — the event IS the notification.
///
/// 2. **Periodic** (throttled): coaching snapshots and tips are derived
///    from the full coaching output, so they're persisted via polling
///    with throttling/deduplication.
///
/// This dual approach gives us:
/// - Zero-latency persistence for discrete business events (slot, alert)
/// - Controlled write frequency for continuous state (snapshot, tip)
final class CoachingPersistenceUseCase {

    private let persistence: SessionPersistence

    // MARK: - Tracking State (for periodic persist only)

    private var lastSnapshotTime: TimeInterval = 0
    private var lastPersistedTipAdvice: String?
    private var sessionId: UUID?

    init(persistence: SessionPersistence = .shared) {
        self.persistence = persistence
    }

    // MARK: - Event Subscription

    /// Wire to the coaching event bus. Called once during coordinator init.
    func subscribe(to bus: CoachingEventBus) {
        bus.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: CoachingEvent) {
        guard let sessionId else { return }

        switch event {
        case .slotCaptured(let slot, _, _):
            persistence.saveMemorySlot(SessionPersistence.PersistedMemorySlot(
                sessionId: sessionId,
                key: slot.key,
                value: slot.value,
                movement: slot.movement,
                source: slot.source,
                confidence: slot.confidence,
                timestamp: slot.timestamp,
                previousValue: nil
            ))

        case .alertDetected(let alert, let elapsed):
            let typeStr: String = {
                switch alert.type {
                case .objection:    return "objection"
                case .buyingSignal: return "buying_signal"
                case .authority:    return "authority"
                case .competitor:   return "competitor"
                }
            }()
            persistence.saveCommercialAlert(SessionPersistence.PersistedAlert(
                sessionId: sessionId,
                timestamp: elapsed,
                alertType: typeStr,
                category: alert.category,
                message: alert.message,
                strength: alert.strength,
                matchedText: nil
            ))

        case .movementChanged:
            // Movement changes are captured in snapshots — no separate table.
            // The event is available for future subscribers (analytics, notifications).
            break
        }
    }

    // MARK: - Session Lifecycle

    func start(sessionId: UUID) {
        self.sessionId = sessionId
        lastSnapshotTime = 0
        lastPersistedTipAdvice = nil
    }

    func reset() {
        sessionId = nil
        lastSnapshotTime = 0
        lastPersistedTipAdvice = nil
    }

    // MARK: - Periodic Persist (snapshots + tips only)

    /// Persist throttled coaching state. Called every ~500ms from the coaching pipeline.
    /// Only handles snapshots and tips — slots and alerts come via events.
    func persistPeriodic(
        output: CoachingOutput,
        elapsed: TimeInterval
    ) {
        guard let sessionId else { return }
        persistSnapshot(output: output, sessionId: sessionId, elapsed: elapsed)
        persistTip(output: output, sessionId: sessionId, elapsed: elapsed)
    }

    // MARK: - Final Flush

    /// Force-persist final snapshot and post-call report.
    /// Slots and alerts are already persisted via events — no flush needed for those.
    func flush(
        output: CoachingOutput?,
        elapsed: TimeInterval,
        report: PostCallReport
    ) {
        guard let sessionId else { return }

        if let output {
            persistSnapshotImmediate(output: output, sessionId: sessionId, elapsed: elapsed)
        }

        persistence.saveReport(sessionId: sessionId, report: report)
        Log.persistence.info("Post-call report saved for session \(sessionId.uuidString.prefix(8))")
    }

    // MARK: - Private: Snapshot

    private func persistSnapshot(
        output: CoachingOutput,
        sessionId: UUID,
        elapsed: TimeInterval
    ) {
        guard elapsed - lastSnapshotTime >= CoachingThresholds.snapshotInterval else { return }
        lastSnapshotTime = elapsed
        persistSnapshotImmediate(output: output, sessionId: sessionId, elapsed: elapsed)
    }

    private func persistSnapshotImmediate(
        output: CoachingOutput,
        sessionId: UUID,
        elapsed: TimeInterval
    ) {
        persistence.saveCoachingSnapshot(SessionPersistence.CoachingSnapshot(
            sessionId: sessionId,
            timestamp: elapsed,
            movement: output.movement,
            act: output.act,
            isManualOverride: output.isManualOverride,
            fluidityScore: output.fluidityScore,
            readinessScore: output.readinessScore,
            speakerBalanceMyRatio: output.speakerBalance.myRatio,
            speakerBalanceHealthy: output.speakerBalance.isHealthy,
            focusText: output.focusNow,
            actionPhrase: output.suggestedAction.personalizedPhrase
        ))
    }

    // MARK: - Private: Tips

    private func persistTip(
        output: CoachingOutput,
        sessionId: UUID,
        elapsed: TimeInterval
    ) {
        guard let tip = output.activeTip, tip.advice != lastPersistedTipAdvice else { return }
        lastPersistedTipAdvice = tip.advice
        persistence.saveTip(SessionPersistence.PersistedTip(
            sessionId: sessionId,
            timestamp: elapsed,
            advice: tip.advice,
            trigger: tip.trigger,
            urgency: tip.urgency.rawValue,
            movement: output.movement,
            alternatives: tip.alternatives
        ))
    }
}
