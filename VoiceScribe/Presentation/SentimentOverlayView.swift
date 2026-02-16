import SwiftUI

// MARK: - Sentiment Display Components
//
// Pure data-driven views for displaying emotion/sentiment state.
// No store dependencies — they receive data via parameters.

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
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.12))
                    Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 1)
                        .offset(x: geo.size.width / 2)
                    
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

// MARK: - Prosodic Pill

struct ProsodicPill: View {
    let icon: String
    let text: String
    var active: Bool = true
    var color: Color = .secondary
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(.caption2, design: .monospaced))
        }
        .foregroundStyle(active ? color : Color.gray.opacity(0.3))
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
                    Path { p in p.move(to: .init(x: 0, y: h/2)); p.addLine(to: .init(x: w, y: h/2)) }
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                    sparkline(values: data.map(\.emotion.valence), w: w, h: h)
                        .stroke(LinearGradient(colors: [.red, .orange, .gray, .mint, .green], startPoint: .bottom, endPoint: .top), lineWidth: 1.5)
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

// MARK: - Compact Indicator (for header bar / menu bar)

struct SentimentIndicator: View {
    let emotion: EmotionalState
    
    var body: some View {
        HStack(spacing: 3) {
            Text(emotion.label.emoji).font(.system(size: 12))
            Text(emotion.label.rawValue).font(.caption2).foregroundStyle(emotion.label.color)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
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
            Image(systemName: "arrow.right").font(.caption2)
            Text(to.emoji)
            Text(to.rawValue).font(.caption).fontWeight(.medium).foregroundStyle(to.color)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
    }
}
