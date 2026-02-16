import SwiftUI

// MARK: - Coaching Panel (the main coaching UI block)

struct CoachingPanelView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @State private var showAlternatives = false
    @State private var selectedAlternative: Int? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // ====== Emotion Row: emoji + label + gauges ======
            HStack(spacing: 12) {
                // Animated emoji
                Text(engine.currentEmotion.label.emoji)
                    .font(.system(size: 36))
                    .animation(.easeInOut(duration: 0.3), value: engine.currentEmotion.label)
                    .accessibilityLabel(engine.currentEmotion.label.rawValue)
                
                // Label + signal
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(engine.currentEmotion.label.rawValue)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(engine.currentEmotion.label.color)
                        
                        Text(engine.currentEmotion.label.commercialSignal.rawValue)
                            .font(.caption)
                    }
                    
                    // Confidence bar
                    HStack(spacing: 4) {
                        Text("Confiance")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.15))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(engine.currentEmotion.label.color.opacity(0.5))
                                    .frame(width: geo.size.width * CGFloat(engine.currentEmotion.confidence))
                                    .animation(.easeOut(duration: 0.3), value: engine.currentEmotion.confidence)
                            }
                        }
                        .frame(width: 50, height: 4)
                        
                        Text("\(Int(engine.currentEmotion.confidence * 100))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Mini VAD gauges
                VStack(alignment: .trailing, spacing: 3) {
                    DimensionGauge(label: "Valence", value: engine.currentEmotion.valence, negColor: .red, posColor: .green)
                    DimensionGauge(label: "Énergie", value: engine.currentEmotion.arousal, negColor: .purple, posColor: .orange)
                    DimensionGauge(label: "Assurance", value: engine.currentEmotion.dominance, negColor: .orange, posColor: .blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            // ====== Prosodic Indicators ======
            HStack(spacing: 14) {
                ProsodicPill(icon: "waveform", text: "\(Int(engine.currentFeatures.pitchHz)) Hz",
                             active: engine.currentFeatures.pitchHz > 0)
                
                ProsodicPill(icon: "metronome", text: "\(String(format: "%.1f", engine.currentFeatures.speechRate)) syl/s",
                             active: engine.currentFeatures.speechRate > 0)
                
                ProsodicPill(
                    icon: contourIcon(engine.currentFeatures.pitchContour),
                    text: contourLabel(engine.currentFeatures.pitchContour),
                    active: engine.currentFeatures.isSpeech,
                    color: contourColor(engine.currentFeatures.pitchContour)
                )
                
                if engine.currentFeatures.pauseDuration > 0.5 {
                    ProsodicPill(icon: "pause.circle", text: "\(String(format: "%.1f", engine.currentFeatures.pauseDuration))s",
                                 active: true, color: .orange)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            
            Divider().padding(.horizontal, 12)
            
            // ====== Coaching Suggestion (the actionable phrase) ======
            if let suggestion = engine.currentSuggestion {
                VStack(alignment: .leading, spacing: 6) {
                    // Urgency badge + category
                    HStack(spacing: 6) {
                        UrgencyBadge(urgency: suggestion.urgency)
                        
                        Text(suggestion.category.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // Toggle alternatives
                        if !suggestion.alternatives.isEmpty {
                            Button(action: { withAnimation { showAlternatives.toggle() } }) {
                                HStack(spacing: 2) {
                                    Text("Variantes")
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
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 10))
                            .foregroundStyle(suggestion.urgency == .critical ? .red : .accentColor)
                            .padding(.top, 2)
                        
                        Text(suggestion.phrase)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Rationale
                    Text(suggestion.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    // Alternatives (collapsible)
                    if showAlternatives && !suggestion.alternatives.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(suggestion.alternatives.enumerated()), id: \.offset) { index, alt in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("→")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    
                                    Text(alt)
                                        .font(.callout)
                                        .foregroundStyle(selectedAlternative == index ? .primary : .secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(selectedAlternative == index ? Color.accentColor.opacity(0.08) : .clear)
                                .cornerRadius(4)
                                .onTapGesture { selectedAlternative = index }
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.3), value: suggestion.phrase)
            } else if engine.state == .recording {
                HStack {
                    Image(systemName: "ear")
                        .foregroundStyle(.tertiary)
                    Text("En écoute... le coach se prépare")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            
            // ====== Sentiment Sparkline ======
            if !engine.sentimentTimeline.isEmpty && engine.state == .recording {
                SentimentSparkline(points: engine.sentimentTimeline)
                    .frame(height: 20)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
        .background(coachingBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onChange(of: engine.currentSuggestion?.phrase) { _, _ in
            selectedAlternative = nil
            showAlternatives = false
        }
    }
    
    // MARK: - Styling
    
    var coachingBackground: some ShapeStyle {
        if let s = engine.currentSuggestion {
            switch s.urgency {
            case .critical: return AnyShapeStyle(Color.red.opacity(0.04))
            case .high: return AnyShapeStyle(Color.orange.opacity(0.03))
            default: return AnyShapeStyle(Color.primary.opacity(0.02))
            }
        }
        return AnyShapeStyle(Color.primary.opacity(0.02))
    }
    
    var borderColor: Color {
        if let s = engine.currentSuggestion {
            switch s.urgency {
            case .critical: return .red.opacity(0.3)
            case .high: return .orange.opacity(0.2)
            default: return .clear
            }
        }
        return .clear
    }
    
    func contourIcon(_ c: PitchContour) -> String {
        switch c { case .rising: "arrow.up.right"; case .falling: "arrow.down.right"; case .peaked: "arrow.up"; case .dipped: "arrow.down"; case .flat: "arrow.right" }
    }
    func contourLabel(_ c: PitchContour) -> String {
        switch c { case .rising: "Montant"; case .falling: "Descendant"; case .peaked: "Pic"; case .dipped: "Creux"; case .flat: "Plat" }
    }
    func contourColor(_ c: PitchContour) -> Color {
        switch c { case .rising: .orange; case .falling: .blue; case .peaked: .red; case .dipped: .purple; case .flat: .gray }
    }
}

// MARK: - Dimension Gauge (Valence/Arousal/Dominance)

struct DimensionGauge: View {
    let label: String
    let value: Float  // -1 to 1
    let negColor: Color
    let posColor: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 55, alignment: .trailing)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.12))
                    
                    // Center marker
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 1)
                        .offset(x: geo.size.width / 2)
                    
                    // Bar
                    let norm = CGFloat((value + 1) / 2)
                    let barWidth = abs(norm - 0.5) * geo.size.width
                    let barOffset = norm >= 0.5 ? geo.size.width / 2 : geo.size.width / 2 - barWidth
                    let barColor = value >= 0 ? posColor : negColor
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.5))
                        .frame(width: barWidth)
                        .offset(x: barOffset)
                        .animation(.easeOut(duration: 0.2), value: value)
                }
            }
            .frame(width: 60, height: 5)
        }
    }
}

// MARK: - Urgency Badge

struct UrgencyBadge: View {
    let urgency: CoachingSuggestionEngine.SuggestionUrgency
    
    var body: some View {
        Text(urgency.rawValue)
            .font(.system(.caption2, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }
    
    var backgroundColor: Color {
        switch urgency {
        case .critical: return .red.opacity(0.2)
        case .high: return .orange.opacity(0.2)
        case .medium: return .yellow.opacity(0.15)
        case .low: return .gray.opacity(0.1)
        }
    }
    
    var foregroundColor: Color {
        switch urgency {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .primary
        case .low: return .secondary
        }
    }
}

// MARK: - Prosodic Pill

struct ProsodicPill: View {
    let icon: String
    let text: String
    var active: Bool = true
    var color: Color = .secondary
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(.caption2, design: .monospaced))
        }
        .foregroundStyle(active ? color : .quaternary)
    }
}

// MARK: - Sentiment Sparkline

struct SentimentSparkline: View {
    let points: [SentimentPoint]
    
    var body: some View {
        GeometryReader { geo in
            let data = Array(points.suffix(60))
            guard data.count > 1 else { return AnyView(EmptyView()) }
            
            let w = geo.size.width, h = geo.size.height
            
            return AnyView(
                ZStack {
                    // Zero line
                    Path { p in p.move(to: .init(x: 0, y: h/2)); p.addLine(to: .init(x: w, y: h/2)) }
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                    
                    // Valence
                    sparkline(values: data.map(\.emotion.valence), w: w, h: h)
                        .stroke(LinearGradient(colors: [.red, .orange, .gray, .mint, .green], startPoint: .bottom, endPoint: .top), lineWidth: 1.5)
                    
                    // Dominance (dotted)
                    sparkline(values: data.map(\.emotion.dominance), w: w, h: h)
                        .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            )
        }
    }
    
    private func sparkline(values: [Float], w: CGFloat, h: CGFloat) -> Path {
        Path { path in
            for (i, v) in values.enumerated() {
                let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                let y = h * CGFloat(1 - (v + 1) / 2)
                if i == 0 { path.move(to: .init(x: x, y: y)) }
                else { path.addLine(to: .init(x: x, y: y)) }
            }
        }
    }
}

// MARK: - Compact Indicator (for header bar)

struct SentimentIndicator: View {
    let emotion: EmotionalState
    
    var body: some View {
        HStack(spacing: 3) {
            Text(emotion.label.emoji)
                .font(.system(size: 12))
            Text(emotion.label.rawValue)
                .font(.caption2)
                .foregroundStyle(emotion.label.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(emotion.label.color.opacity(0.1))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.3), value: emotion.label)
    }
}

// MARK: - Shift Notification (toast-like)

struct SentimentShiftBanner: View {
    let from: EmotionLabel
    let to: EmotionLabel
    
    var body: some View {
        HStack(spacing: 8) {
            Text(from.emoji)
            Image(systemName: "arrow.right")
                .font(.caption2)
            Text(to.emoji)
            Text(to.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(to.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
    }
}
