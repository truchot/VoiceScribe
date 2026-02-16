import SwiftUI

/// Top bar: status indicator, movement pill, emotion, hotkey badge, overlay toggle.
struct HeaderBar: View {
    @EnvironmentObject var recording: RecordingStore
    @EnvironmentObject var sentiment: SentimentStore
    @EnvironmentObject var coaching: CoachingStore
    @EnvironmentObject var transcription: TranscriptionStore
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var overlay: OverlayManager
    @Binding var showHistory: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { showHistory.toggle() }) {
                Image(systemName: "sidebar.left").font(.system(size: 12))
            }.buttonStyle(.plain)
            
            Circle().fill(recording.state.statusColor).frame(width: 8, height: 8)
            Text(recording.state.statusText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            
            if env.coordinator.hotkeys.isEnabled {
                Text("⌥⇧R").font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.purple.opacity(0.15)).foregroundStyle(.purple).clipShape(Capsule())
            }
            
            // Overlay toggle
            if recording.state == .recording {
                Button(action: { env.toggleOverlay() }) {
                    Image(systemName: overlay.isVisible ? "pip.exit" : "pip.enter")
                        .font(.system(size: 11))
                        .foregroundStyle(overlay.isVisible ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Overlay compact (⌥⇧O)")
            }
            
            Spacer()
            
            // Movement pill
            if recording.state == .recording, let output = coaching.coachingOutput {
                MovementPill(movement: output.movement, act: output.act)
            }
            
            // Emotion pill
            if recording.state == .recording && sentiment.currentEmotion.confidence > 0.3 {
                SentimentIndicator(emotion: sentiment.currentEmotion)
            }
            
            // Commercial alert mini-indicator
            if recording.state == .recording, let alert = sentiment.commercialAlert {
                CommercialAlertPill(alert: alert)
            }
            
            if let session = transcription.currentSession {
                Text(session.formattedDuration).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

// MARK: - Small components (no @EnvironmentObject — pure data)

struct MovementPill: View {
    let movement: ConversationMovement
    let act: ConversationAct
    
    var body: some View {
        HStack(spacing: 3) {
            Text(movement.emoji).font(.system(size: 10))
            Text(movement.name).font(.system(.caption2, weight: .medium))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(act.uiColor.opacity(0.1))
        .foregroundStyle(act.uiColor)
        .clipShape(Capsule())
    }
}

struct CommercialAlertPill: View {
    let alert: CommercialAlert
    
    var body: some View {
        Text(alertEmoji)
            .font(.system(size: 10))
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(alertColor.opacity(0.15))
            .clipShape(Capsule())
            .help(alert.message)
            .transition(.scale.combined(with: .opacity))
    }
    
    private var alertEmoji: String {
        switch alert.type {
        case .objection: "⚠️"
        case .buyingSignal: "✅"
        case .authority: "👤"
        case .competitor: "🏢"
        }
    }
    
    private var alertColor: Color {
        switch alert.type {
        case .objection: .red
        case .buyingSignal: .green
        case .authority: .orange
        case .competitor: .yellow
        }
    }
}
