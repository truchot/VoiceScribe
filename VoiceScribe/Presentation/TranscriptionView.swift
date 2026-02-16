import SwiftUI

/// Scrollable transcription list — only observes TranscriptionStore.
struct TranscriptionView: View {
    @EnvironmentObject var transcription: TranscriptionStore
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let session = transcription.currentSession {
                        ForEach(session.segments) { seg in SegmentRow(segment: seg).id(seg.id) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if !transcription.liveTextMic.isEmpty {
                            LiveRow(text: transcription.liveTextMic, icon: "mic.fill", color: .blue,
                                    isInferring: transcription.isInferringMic)
                        }
                        if !transcription.liveTextSystem.isEmpty {
                            LiveRow(text: transcription.liveTextSystem, icon: "speaker.wave.2.fill", color: .green,
                                    isInferring: transcription.isInferringSystem)
                        }
                    }.id("live")
                    if transcription.currentSession?.segments.isEmpty ?? true && transcription.liveTextMic.isEmpty && transcription.liveTextSystem.isEmpty {
                        EmptyTranscriptionView()
                    }
                }.padding(.vertical, 12)
            }
            .onChange(of: transcription.currentSession?.segments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let id = transcription.currentSession?.segments.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }
}

struct SegmentRow: View {
    let segment: TranscriptionSegment
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(segment.formattedTime)
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 38, alignment: .trailing)
            if let s = segment.sentiment, s.confidence > 0.3 {
                Text(s.label.emoji).font(.system(size: 12)).help("\(s.label.rawValue)")
            }
            Text(segment.speaker.rawValue)
                .font(.system(.caption2, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(speakerColor.opacity(0.15)).foregroundStyle(speakerColor).clipShape(Capsule())
            Text(segment.text).font(.body).textSelection(.enabled).lineLimit(nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 2)
        .background(isHovered ? Color.primary.opacity(0.03) : .clear)
        .cornerRadius(4).onHover { isHovered = $0 }
    }
    var speakerColor: Color { switch segment.speaker { case .me: .blue; case .other: .green; case .unknown: .gray } }
}

struct LiveRow: View {
    let text: String; let icon: String; let color: Color
    var isInferring: Bool = false
    @State private var pulse = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TypingDots(color: color).frame(width: 38, alignment: .trailing)
            ZStack {
                Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color)
                if isInferring {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 9))
                        .foregroundStyle(color)
                        .opacity(pulse ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                }
            }
            Text(text).font(.body).foregroundStyle(.secondary).italic()
        }.padding(.horizontal, 16)
    }
}

struct TypingDots: View {
    var color: Color = .accentColor
    @State private var dot = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 2) { ForEach(0..<3, id: \.self) { i in Circle().fill(color).frame(width: 4, height: 4).opacity(i <= dot ? 1 : 0.3) } }
            .onReceive(timer) { _ in dot = (dot + 1) % 3 }
    }
}

struct EmptyTranscriptionView: View {
    @EnvironmentObject var recording: RecordingStore
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile").font(.system(size: 48)).foregroundStyle(.quaternary)
            Text(recording.state == .recording ? "En écoute... Coach actif" : "Appuyez sur ● pour démarrer")
                .font(.title3).foregroundStyle(.secondary)
            if recording.state != .recording {
                VStack(spacing: 4) {
                    Text("⌥⇧R enregistrer • ⌥⇧S stop • ⌥⇧N nouvelle session")
                    Text("⌥⇧O overlay compact • 11 mouvements • Coach temps réel")
                }.font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }.frame(maxWidth: .infinity).padding(32)
    }
}
