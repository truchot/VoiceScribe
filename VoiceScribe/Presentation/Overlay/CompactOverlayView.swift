import SwiftUI

/// The compact coaching overlay shown during live calls.
///
/// Design principles:
/// - ONE glance = know what to do next
/// - No scrolling — everything visible at once
/// - Color = urgency (green/orange/red)
/// - Text = minimal, actionable
/// - Click movement pills to override
///
/// Layout (~300px wide):
/// ┌──────────────────────────────────┐
/// │ ● REC  03:42  😊  🎤40/🔊60    │ ← Status strip
/// │ ☕→🗺️→🌍→🔍→⛏️→🌟→🧭→🎯→💬→🤝→📬 │ ← Movement rail
/// ├──────────────────────────────────┤
/// │ 🔍 Enjeux                       │
/// │ Trouvez la douleur principale.  │ ← Focus (1 line)
/// │                                 │
/// │ « Dans tout ce que vous avez    │ ← Action phrase
/// │   décrit, qu'est-ce qui vous    │
/// │   prend le plus d'énergie ? »   │
/// ├──────────────────────────────────┤
/// │ ⚠️ Vous parlez trop — question  │ ← Tip (only if urgent)
/// ├──────────────────────────────────┤
/// │ 😰 Empathie d'abord             │ ← Emotion (only if notable)
/// └──────────────────────────────────┘

struct CompactOverlayView: View {
    @EnvironmentObject var recording: RecordingStore
    @EnvironmentObject var coaching: CoachingStore
    @EnvironmentObject var sentiment: SentimentStore
    @EnvironmentObject var audio: AudioStore
    @EnvironmentObject var env: AppEnvironment
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle + status strip
            statusStrip
            
            if let output = coaching.coachingOutput {
                // Commercial alert (text-detected objection/buying signal)
                if let alert = sentiment.commercialAlert {
                    commercialAlertStrip(alert: alert)
                }
                
                // Movement rail
                movementRail(output: output)
                
                Divider().opacity(0.3)
                
                // Core: focus + action
                coreSection(output: output)
                
                // Tip (only if attention/action urgency)
                if let tip = output.activeTip, tip.urgency != .info {
                    Divider().opacity(0.3)
                    tipStrip(tip: tip)
                }
                
                // Emotion coaching (only if notable)
                if let emo = output.emotionCoaching {
                    Divider().opacity(0.3)
                    emotionStrip(coaching: emo)
                }
                
                // Transition nudge
                if let nudge = output.transitionNudge {
                    Divider().opacity(0.3)
                    transitionStrip(nudge: nudge)
                }
            } else {
                // Waiting state
                HStack {
                    Image(systemName: "ear").foregroundStyle(.tertiary)
                    Text("En écoute...").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
            }
            
            // Controls (visible on hover)
            if isHovering {
                Divider().opacity(0.3)
                controlStrip
            }
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
    
    // MARK: - Status Strip (always visible)
    
    private var statusStrip: some View {
        HStack(spacing: 6) {
            // Drag indicator
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
            
            // Recording status
            Circle()
                .fill(recording.state == .recording ? .red : .orange)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .fill(.red.opacity(0.4))
                        .frame(width: 12, height: 12)
                        .opacity(recording.state == .recording ? 1 : 0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recording.state)
                )
            
            // Elapsed
            Text(formatElapsed(recording.elapsed))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Emotion pill
            if sentiment.currentEmotion.confidence > 0.3 {
                Text(sentiment.currentEmotion.label.emoji)
                    .font(.system(size: 12))
                    .animation(.easeInOut(duration: 0.3), value: sentiment.currentEmotion.label)
            }
            
            // Speaker balance (ultra compact)
            if let output = coaching.coachingOutput {
                let b = output.speakerBalance
                HStack(spacing: 2) {
                    Image(systemName: b.isHealthy ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 7))
                        .foregroundStyle(b.isHealthy ? .green : .orange)
                    Text("\(Int(b.myRatio * 100))/\(Int((1 - b.myRatio) * 100))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.02))
    }
    
    // MARK: - Movement Rail
    
    private func movementRail(output: ConversationCoach.CoachingOutput) -> some View {
        HStack(spacing: 0) {
            ForEach(ConversationMovement.allCases, id: \.rawValue) { m in
                let isCurrent = m == output.movement
                let isPast = m.rawValue < output.movement.rawValue
                
                Button(action: { coaching.overrideMovement(m) }) {
                    Text(m.emoji)
                        .font(.system(size: isCurrent ? 13 : 9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(
                            isCurrent ? m.act.uiColor.opacity(0.2) :
                            isPast ? Color.green.opacity(0.05) : .clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .buttonStyle(.plain)
                .help(m.name)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
    
    // MARK: - Core Section (focus + action)
    
    private func coreSection(output: ConversationCoach.CoachingOutput) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Movement name + fluidity
            HStack(spacing: 4) {
                Text(output.movement.emoji).font(.system(size: 12))
                Text(output.movement.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(output.act.uiColor)
                
                if output.isManualOverride {
                    Text("✋")
                        .font(.system(size: 8))
                        .help("Mode manuel")
                }
                
                Spacer()
                
                // Readiness dots
                readinessDots(score: output.readinessScore)
            }
            
            // Focus (1-2 lines max)
            Text(output.focusNow)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            // Action phrase
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 7))
                    .foregroundStyle(output.act.uiColor)
                    .padding(.top, 2)
                
                Text(output.suggestedAction.personalizedPhrase)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
    
    // MARK: - Tip Strip (only urgent)
    
    private func tipStrip(tip: ConversationCoach.ActiveTip) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: tip.urgency == .action ? "bolt.fill" : "exclamationmark.triangle")
                .font(.system(size: 9))
                .foregroundStyle(tip.urgency == .action ? .red : .orange)
            
            Text(tip.advice)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (tip.urgency == .action ? Color.red : Color.orange).opacity(0.06)
        )
    }
    
    // MARK: - Emotion Strip
    
    private func emotionStrip(coaching: ConversationCoach.EmotionCoaching) -> some View {
        HStack(spacing: 4) {
            Text(coaching.emoji).font(.system(size: 11))
            Text(coaching.empathyPhrase)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
    
    // MARK: - Transition Strip
    
    private func transitionStrip(nudge: ConversationCoach.TransitionNudge) -> some View {
        Button(action: { coaching.overrideMovement(nudge.target) }) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
                
                Text(nudge.reason)
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(nudge.target.emoji) \(nudge.target.shortLabel)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
    
    // MARK: - Control Strip (on hover)
    
    private var controlStrip: some View {
        HStack(spacing: 12) {
            // Pause / Resume
            Button(action: { Task { await env.toggleRecording() } }) {
                Image(systemName: recording.state == .recording ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(recording.state == .recording ? .orange : .green)
            }.buttonStyle(.plain)
            
            // Stop
            Button(action: { Task { await env.stopRecording() } }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.6))
            }.buttonStyle(.plain)
            
            Spacer()
            
            // Opacity hint
            Text("⌥⇧O fermer")
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    // MARK: - Commercial Alert Strip (text-detected signals)
    
    private func commercialAlertStrip(alert: CommercialAlert) -> some View {
        HStack(spacing: 4) {
            Text(alert.message)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
            
            Spacer()
            
            Button(action: { sentiment.dismissAlert() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(alertBackground(alert))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: alert.message)
    }
    
    private func alertBackground(_ alert: CommercialAlert) -> some ShapeStyle {
        switch alert.type {
        case .objection:
            return AnyShapeStyle(Color.red.opacity(0.12))
        case .buyingSignal:
            return AnyShapeStyle(Color.green.opacity(0.12))
        case .authority:
            return AnyShapeStyle(Color.orange.opacity(0.12))
        case .competitor:
            return AnyShapeStyle(Color.yellow.opacity(0.12))
        }
    }
    
    // MARK: - Helpers
    
    private func readinessDots(score: Float) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Float(i) / 5.0 < score ? .green : Color.gray.opacity(0.2))
                    .frame(width: 3, height: 3)
            }
        }
        .help("Mémoire: \(Int(score * 100))%")
    }
    
    private var borderColor: Color {
        guard let output = coaching.coachingOutput else { return .clear }
        if let tip = output.activeTip {
            switch tip.urgency {
            case .action: return .red
            case .attention: return .orange
            case .info: return output.act.uiColor
            }
        }
        return output.act.uiColor
    }
    
    private func formatElapsed(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Preview

#if DEBUG
struct CompactOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        CompactOverlayView()
            .environmentObject(RecordingStore())
            .environmentObject(CoachingStore())
            .environmentObject(SentimentStore())
            .environmentObject(AudioStore())
            .environmentObject(AppEnvironment())
            .frame(width: 300, height: 250)
            .background(.black.opacity(0.8))
    }
}
#endif
