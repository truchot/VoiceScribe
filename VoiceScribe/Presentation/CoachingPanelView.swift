import SwiftUI

// MARK: - Main Coaching Panel

struct CoachingPanel: View {
    @EnvironmentObject var coaching: CoachingStore
    @EnvironmentObject var sentiment: SentimentStore
    @State private var showAlternatives = false
    @State private var showSlots = false
    @State private var showMemoryEditor = false
    
    var body: some View {
        if let output = coaching.coachingOutput {
            VStack(spacing: 0) {
                // Commercial alert (text-detected objection/buying signal)
                if let alert = sentiment.commercialAlert {
                    CommercialAlertBanner(alert: alert, onDismiss: { sentiment.dismissAlert() })
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                
                // Movement bar
                MovementProgressBar(
                    current: output.movement,
                    onTap: { coaching.overrideMovement($0) }
                )
                .padding(.horizontal, 8)
                .padding(.top, 6)
                
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                
                // Golden rule
                HStack(spacing: 6) {
                    Text("✨")
                        .font(.system(size: 11))
                    Text(output.goldenRule)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .italic()
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                
                // Focus
                FocusRow(output: output)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                
                Divider().padding(.horizontal, 8)
                
                // Suggested action
                ActionRow(output: output, showAlternatives: $showAlternatives)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                
                // Active tip (if any)
                if let tip = output.activeTip {
                    Divider().padding(.horizontal, 8)
                    TipRow(tip: tip)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                
                // Emotion coaching (if active)
                if let emo = output.emotionCoaching {
                    Divider().padding(.horizontal, 8)
                    EmotionRow(coaching: emo)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                
                Divider().padding(.horizontal, 8)
                
                // Bottom bar: slots + balance + transition
                HStack(alignment: .top, spacing: 12) {
                    // Memory slots
                    SlotStatusView(slots: output.slotStatus, show: $showSlots, readiness: output.readinessScore)
                    
                    Spacer()
                    
                    // Balance
                    MiniBalance(balance: output.speakerBalance)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                
                // Transition nudge
                if let nudge = output.transitionNudge {
                    Divider().padding(.horizontal, 8)
                    TransitionRow(nudge: nudge, onAccept: {
                        coaching.overrideMovement(nudge.target)
                    })
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
            .background(Color.primary.opacity(0.015))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(actBorderColor(output.act).opacity(0.15), lineWidth: 1)
            )
            .onChange(of: output.movement) { _, _ in
                showAlternatives = false
            }
        }
    }
    
    func actBorderColor(_ act: ConversationAct) -> Color {
        switch act {
        case .connexion: return .cyan
        case .exploration: return .blue
        case .solution: return .purple
        case .suivi: return .mint
        }
    }
}

// MARK: - Movement Progress Bar

struct MovementProgressBar: View {
    let current: ConversationMovement
    var onTap: ((ConversationMovement) -> Void)?
    
    var body: some View {
        VStack(spacing: 2) {
            // Act labels
            HStack(spacing: 0) {
                ActLabel(act: .connexion, movements: [.accueil, .cadrage, .univers], current: current)
                ActLabel(act: .exploration, movements: [.enjeux, .profondeur, .vision, .qualification], current: current)
                ActLabel(act: .solution, movements: [.proposition, .dialogue, .engagement], current: current)
                ActLabel(act: .suivi, movements: [.suivi], current: current)
            }
            
            // Movement pills
            HStack(spacing: 1) {
                ForEach(ConversationMovement.allCases, id: \.rawValue) { m in
                    let isCurrent = m == current
                    let isPast = m.rawValue < current.rawValue
                    
                    Button(action: { onTap?(m) }) {
                        VStack(spacing: 1) {
                            Text(m.emoji)
                                .font(.system(size: isCurrent ? 12 : 9))
                            Text(m.shortLabel)
                                .font(.system(size: 7, weight: isCurrent ? .bold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(
                            isCurrent ? movementColor(m).opacity(0.15) :
                            isPast ? Color.green.opacity(0.05) : .clear
                        )
                        .foregroundStyle(isCurrent ? movementColor(m) : isPast ? Color.secondary : Color.gray.opacity(0.3))
                        .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help(m.name)
                }
            }
        }
    }
    
    func movementColor(_ m: ConversationMovement) -> Color {
        switch m.act {
        case .connexion: return .cyan
        case .exploration: return .blue
        case .solution: return .purple
        case .suivi: return .mint
        }
    }
}

struct ActLabel: View {
    let act: ConversationAct
    let movements: [ConversationMovement]
    let current: ConversationMovement
    
    var isActive: Bool { movements.contains(current) }
    
    var body: some View {
        Text(act.rawValue.uppercased())
            .font(.system(size: 7, weight: isActive ? .bold : .regular, design: .rounded))
            .foregroundStyle(isActive ? act.uiColor : Color.gray.opacity(0.3))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Focus Row

struct FocusRow: View {
    let output: ConversationCoach.CoachingOutput
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconForMovement(output.movement))
                .font(.system(size: 14))
                .foregroundStyle(colorForAct(output.act))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(output.movement.name)
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(colorForAct(output.act))
                    
                    if output.isManualOverride {
                        Text("Manuel")
                            .font(.system(size: 7, weight: .medium))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Fluidity score
                    HStack(spacing: 2) {
                        Circle().fill(fluidityColor(output.fluidityScore)).frame(width: 5, height: 5)
                        Text("\(Int(output.fluidityScore * 100))%")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .help("Fluidité de la conversation")
                }
                
                Text(output.focusNow)
                    .font(.system(.callout, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    func iconForMovement(_ m: ConversationMovement) -> String {
        switch m {
        case .accueil: return "hand.wave"
        case .cadrage: return "rectangle.and.text.magnifyingglass"
        case .univers: return "globe"
        case .enjeux: return "magnifyingglass"
        case .profondeur: return "arrow.down.to.line"
        case .vision: return "sparkles"
        case .qualification: return "compass.drawing"
        case .proposition: return "target"
        case .dialogue: return "bubble.left.and.bubble.right"
        case .engagement: return "handshake"
        case .suivi: return "envelope"
        }
    }
    
    func colorForAct(_ act: ConversationAct) -> Color {
        switch act {
        case .connexion: return .cyan
        case .exploration: return .blue
        case .solution: return .purple
        case .suivi: return .mint
        }
    }
    
    func fluidityColor(_ score: Float) -> Color {
        if score > 0.7 { return .green }
        if score > 0.4 { return .orange }
        return .red
    }
}

// MARK: - Action Row

struct ActionRow: View {
    let output: ConversationCoach.CoachingOutput
    @Binding var showAlternatives: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(output.suggestedAction.energy.rawValue)
                    .font(.system(.caption2, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                
                Spacer()
                
                if !output.suggestedAction.alternatives.isEmpty {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAlternatives.toggle() } }) {
                        HStack(spacing: 2) {
                            Text(showAlternatives ? "Masquer" : "+\(output.suggestedAction.alternatives.count)")
                                .font(.caption2)
                            Image(systemName: showAlternatives ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Main phrase (personalized)
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 3)
                
                Text(output.suggestedAction.personalizedPhrase)
                    .font(.system(.body, weight: .medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Text(output.suggestedAction.context)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            if showAlternatives {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(output.suggestedAction.personalizedAlternatives.enumerated()), id: \.offset) { _, alt in
                        HStack(alignment: .top, spacing: 4) {
                            Text("→").font(.caption).foregroundStyle(.quaternary)
                            Text(alt).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Tip Row

struct TipRow: View {
    let tip: ConversationCoach.ActiveTip
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: urgencyIcon)
                .font(.system(size: 11))
                .foregroundStyle(urgencyColor)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(tip.urgency.rawValue.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(urgencyColor)
                    Text("• \(tip.trigger)")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                }
                
                Text(tip.advice)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !tip.alternatives.isEmpty {
                    ForEach(Array(tip.alternatives.prefix(2).enumerated()), id: \.offset) { _, alt in
                        Text("💬 \(alt)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(6)
        .background(urgencyColor.opacity(0.05))
        .cornerRadius(6)
    }
    
    var urgencyIcon: String {
        switch tip.urgency {
        case .info: return "info.circle"
        case .attention: return "exclamationmark.triangle"
        case .action: return "bolt.fill"
        }
    }
    
    var urgencyColor: Color {
        switch tip.urgency {
        case .info: return .blue
        case .attention: return .orange
        case .action: return .red
        }
    }
}

// MARK: - Emotion Row

struct EmotionRow: View {
    let coaching: ConversationCoach.EmotionCoaching
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(coaching.emoji).font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Émotion : \(coaching.emotion.rawValue)")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.secondary)
                
                Text(coaching.empathyPhrase)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
    }
}

// MARK: - Slot Status

struct SlotStatusView: View {
    let slots: [ConversationCoach.SlotStatus]
    @Binding var show: Bool
    let readiness: Float
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: { withAnimation { show.toggle() } }) {
                HStack(spacing: 4) {
                    let filled = slots.filter(\.filled).count
                    Text("Mémoire \(filled)/\(slots.count)")
                        .font(.system(.caption2, weight: .bold))
                    
                    // Readiness bar
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(readiness > 0.7 ? .green : readiness > 0.4 ? .orange : .red)
                                .frame(width: g.size.width * CGFloat(readiness))
                        }
                    }
                    .frame(width: 40, height: 4)
                    
                    Image(systemName: show ? "chevron.up" : "chevron.down")
                        .font(.system(size: 6))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            
            if show {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    HStack(spacing: 4) {
                        Image(systemName: slot.filled ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundStyle(slot.filled ? Color.green :
                                slot.importance == .critical ? Color.red.opacity(0.6) : Color.gray.opacity(0.5))
                        
                        Text(slot.label)
                            .font(.system(size: 9))
                            .foregroundStyle(slot.filled ? .secondary : .primary)
                            .strikethrough(slot.filled)
                        
                        if let value = slot.value {
                            Text(String(value.prefix(30)))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .lineLimit(1)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Mini Balance

struct MiniBalance: View {
    let balance: MovementDetector.SpeakerBalance
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: balance.isHealthy ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 8))
                    .foregroundStyle(balance.isHealthy ? .green : .orange)
                
                Text("🎤\(Int(balance.myRatio * 100))% / 🔊\(Int((1 - balance.myRatio) * 100))%")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            if let advice = balance.advice {
                Text(advice)
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Transition Row

struct TransitionRow: View {
    let nudge: ConversationCoach.TransitionNudge
    let onAccept: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 12))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(nudge.reason)
                    .font(.caption)
                    .foregroundStyle(.blue)
                
                if !nudge.isReady {
                    Text("⚠️ Infos manquantes — transition possible mais risquée")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            Button(action: onAccept) {
                HStack(spacing: 3) {
                    Text(nudge.target.emoji).font(.system(size: 10))
                    Text(nudge.target.shortLabel)
                        .font(.system(.caption2, weight: .bold))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Commercial Alert Banner (text-detected signals)

struct CommercialAlertBanner: View {
    let alert: CommercialAlert
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForType)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(colorForType)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.message)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(colorForType)
                
                Text("Signal textuel • Force: \(Int(alert.strength * 100))%")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(colorForType.opacity(0.08))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(colorForType.opacity(0.2), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var iconForType: String {
        switch alert.type {
        case .objection: return "exclamationmark.triangle.fill"
        case .buyingSignal: return "checkmark.seal.fill"
        case .authority: return "person.badge.key.fill"
        case .competitor: return "flag.fill"
        }
    }
    
    private var colorForType: Color {
        switch alert.type {
        case .objection: return .red
        case .buyingSignal: return .green
        case .authority: return .orange
        case .competitor: return .yellow
        }
    }
}
