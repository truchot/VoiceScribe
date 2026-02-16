import SwiftUI

// MARK: - Commercial Coach Panel

struct CommercialCoachPanel: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @State private var showObjectives = true
    @State private var showAlternatives = false
    @State private var manualPhaseOverride = false
    
    var body: some View {
        VStack(spacing: 0) {
            // ====== Phase Progress Bar ======
            if let advice = engine.currentAdvice {
                PhaseProgressBar(
                    currentPhase: advice.phase,
                    onPhaseTap: { phase in
                        engine.overridePhase(phase)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                Divider().padding(.horizontal, 12)
                
                // ====== Focus Statement ======
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: advice.phase.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(phaseColor(advice.phase))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(advice.phase.rawValue)
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(phaseColor(advice.phase))
                        
                        Text(advice.focusNow)
                            .font(.system(.callout, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                
                // ====== Suggested Action ======
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(advice.suggestedAction.type.rawValue)
                            .font(.system(.caption2, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(phaseColor(advice.phase).opacity(0.15))
                            .foregroundStyle(phaseColor(advice.phase))
                            .clipShape(Capsule())
                        
                        Spacer()
                        
                        if !advice.suggestedAction.alternatives.isEmpty {
                            Button(action: { withAnimation { showAlternatives.toggle() } }) {
                                HStack(spacing: 2) {
                                    Text(showAlternatives ? "Masquer" : "+\(advice.suggestedAction.alternatives.count) variantes")
                                        .font(.caption2)
                                    Image(systemName: showAlternatives ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Main phrase
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 9))
                            .foregroundStyle(phaseColor(advice.phase))
                            .padding(.top, 3)
                        
                        Text(advice.suggestedAction.phrase)
                            .font(.system(.body, weight: .medium))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Rationale
                    Text(advice.suggestedAction.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    // Alternatives
                    if showAlternatives {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(advice.suggestedAction.alternatives.enumerated()), id: \.offset) { _, alt in
                                HStack(alignment: .top, spacing: 5) {
                                    Text("→").font(.caption).foregroundStyle(.tertiary)
                                    Text(alt).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                
                Divider().padding(.horizontal, 12)
                
                // ====== Objectives Checklist + Watch Signals ======
                HStack(alignment: .top, spacing: 12) {
                    // Objectives
                    VStack(alignment: .leading, spacing: 4) {
                        Button(action: { withAnimation { showObjectives.toggle() } }) {
                            HStack(spacing: 4) {
                                Text("Objectifs")
                                    .font(.system(.caption2, weight: .bold))
                                    .foregroundStyle(.primary)
                                
                                let done = advice.objectives.filter(\.completed).count
                                let total = advice.objectives.count
                                Text("\(done)/\(total)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                
                                Image(systemName: showObjectives ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if showObjectives {
                            ForEach(Array(advice.objectives.enumerated()), id: \.offset) { _, obj in
                                HStack(spacing: 5) {
                                    Image(systemName: obj.completed ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(obj.completed ? .green : .tertiary)
                                    
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(obj.label)
                                            .font(.caption2)
                                            .foregroundStyle(obj.completed ? .secondary : .primary)
                                            .strikethrough(obj.completed)
                                        
                                        if !obj.completed {
                                            Text(obj.hint)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.quaternary)
                                        }
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Watch signals (if any)
                    if !advice.watchFor.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signaux")
                                .font(.system(.caption2, weight: .bold))
                            
                            ForEach(Array(advice.watchFor.enumerated()), id: \.offset) { _, signal in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(signal.detected ? Color.orange : Color.gray.opacity(0.2))
                                        .frame(width: 6, height: 6)
                                    
                                    Text(signal.signal)
                                        .font(.system(size: 9))
                                        .foregroundStyle(signal.detected ? .orange : .quaternary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                
                // ====== Speaker Balance ======
                if let balance = advice.balanceFeedback {
                    Divider().padding(.horizontal, 12)
                    
                    SpeakerBalanceBar(feedback: balance, idealRatio: advice.phase.idealProspectRatio)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                
                // ====== Transition Nudge ======
                if let nudge = advice.transitionNudge {
                    Divider().padding(.horizontal, 12)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 12))
                        
                        Text(nudge)
                            .font(.caption)
                            .foregroundStyle(.blue)
                        
                        Spacer()
                        
                        if let next = advice.phase.next {
                            Button(action: { engine.overridePhase(next) }) {
                                Text("Passer →")
                                    .font(.system(.caption2, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color.primary.opacity(0.015))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .onChange(of: engine.currentAdvice?.phase) { _, _ in
            showAlternatives = false
        }
    }
    
    func phaseColor(_ phase: SalesPhaseDetector.SalesPhase) -> Color {
        switch phase {
        case .ouverture: return .cyan
        case .decouverte: return .blue
        case .qualification: return .indigo
        case .presentation: return .purple
        case .objections: return .orange
        case .closing: return .green
        case .suivi: return .mint
        }
    }
}

// MARK: - Phase Progress Bar

struct PhaseProgressBar: View {
    let currentPhase: SalesPhaseDetector.SalesPhase
    var onPhaseTap: ((SalesPhaseDetector.SalesPhase) -> Void)?
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(SalesPhaseDetector.SalesPhase.allCases.enumerated()), id: \.offset) { index, phase in
                let isCurrent = phase == currentPhase
                let isPast = phaseIndex(phase) < phaseIndex(currentPhase)
                
                Button(action: { onPhaseTap?(phase) }) {
                    VStack(spacing: 2) {
                        Text(phase.emoji)
                            .font(.system(size: isCurrent ? 14 : 10))
                        
                        Text(shortLabel(phase))
                            .font(.system(size: 8, weight: isCurrent ? .bold : .regular))
                            .foregroundStyle(isCurrent ? colorFor(phase) : isPast ? .secondary : .quaternary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(
                        isCurrent ? colorFor(phase).opacity(0.12) :
                        isPast ? Color.gray.opacity(0.05) : .clear
                    )
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                if index < SalesPhaseDetector.SalesPhase.allCases.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 6))
                        .foregroundStyle(isPast ? .secondary : .quaternary)
                }
            }
        }
    }
    
    func shortLabel(_ phase: SalesPhaseDetector.SalesPhase) -> String {
        switch phase {
        case .ouverture: return "Open"
        case .decouverte: return "Décou."
        case .qualification: return "Qualif."
        case .presentation: return "Prés."
        case .objections: return "Object."
        case .closing: return "Close"
        case .suivi: return "Suivi"
        }
    }
    
    func phaseIndex(_ phase: SalesPhaseDetector.SalesPhase) -> Int {
        SalesPhaseDetector.SalesPhase.allCases.firstIndex(of: phase) ?? 0
    }
    
    func colorFor(_ phase: SalesPhaseDetector.SalesPhase) -> Color {
        switch phase {
        case .ouverture: return .cyan
        case .decouverte: return .blue
        case .qualification: return .indigo
        case .presentation: return .purple
        case .objections: return .orange
        case .closing: return .green
        case .suivi: return .mint
        }
    }
}

// MARK: - Speaker Balance Bar

struct SpeakerBalanceBar: View {
    let feedback: CommercialCoachEngine.BalanceFeedback
    let idealRatio: Float
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: feedback.isGood ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(feedback.isGood ? .green : .orange)
                
                Text(feedback.message)
                    .font(.caption2)
                    .foregroundStyle(feedback.isGood ? .secondary : .orange)
            }
            
            // Balance gauge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.1))
                    
                    // Me portion (blue)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(1 - feedback.prospectRatio))
                    
                    // Ideal marker
                    Rectangle()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 2)
                        .offset(x: geo.size.width * CGFloat(1 - idealRatio) - 1)
                    
                    // Labels
                    HStack {
                        Text("🎤 Moi \(Int((1 - feedback.prospectRatio) * 100))%")
                            .font(.system(size: 8, design: .monospaced))
                            .padding(.leading, 4)
                        
                        Spacer()
                        
                        Text("🔊 Prospect \(Int(feedback.prospectRatio * 100))%")
                            .font(.system(size: 8, design: .monospaced))
                            .padding(.trailing, 4)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 16)
        }
    }
}
