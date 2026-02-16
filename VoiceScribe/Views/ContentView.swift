import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @State private var showHistory = false
    @State private var coachingTab: CoachingTab = .commercial
    
    enum CoachingTab: String, CaseIterable {
        case commercial = "Commercial"
        case empathie = "Empathie"
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if showHistory {
                SessionHistoryView(showHistory: $showHistory)
                    .frame(width: 200)
                    .transition(.move(edge: .leading))
                Divider()
            }
            
            VStack(spacing: 0) {
                HeaderBar(showHistory: $showHistory)
                Divider()
                
                if engine.modelLoaded {
                    if engine.systemCaptureAvailable {
                        AppSelectionBar()
                        Divider()
                    }
                    
                    // === COACHING ZONE ===
                    if engine.state == .recording && engine.captureSystemAudio {
                        CoachingZone(tab: $coachingTab)
                        Divider()
                    }
                    
                    TranscriptionView()
                } else {
                    ModelLoadingView()
                }
                
                Divider()
                ControlBar()
            }
        }
        .frame(width: showHistory ? 760 : 580, minHeight: 700)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: showHistory)
        .overlay(alignment: .top) {
            if let shift = engine.lastSentimentShift, engine.state == .recording {
                SentimentShiftBanner(from: shift.from, to: shift.to)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { engine.lastSentimentShift = nil }
                        }
                    }
            }
        }
        .onAppear { Task { await engine.loadModel() } }
    }
}

// MARK: - Coaching Zone (tabbed: Commercial / Empathie)

struct CoachingZone: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @Binding var tab: ContentView.CoachingTab
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                ForEach(ContentView.CoachingTab.allCases, id: \.self) { t in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { tab = t } }) {
                        HStack(spacing: 4) {
                            Image(systemName: t == .commercial ? "chart.line.uptrend.xyaxis" : "brain.head.profile")
                                .font(.system(size: 10))
                            Text(t.rawValue)
                                .font(.system(.caption, weight: tab == t ? .bold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(tab == t ? Color.accentColor.opacity(0.1) : .clear)
                        .foregroundStyle(tab == t ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Phase pill in header
                if let phase = engine.currentAdvice?.phase {
                    HStack(spacing: 3) {
                        Text(phase.emoji)
                            .font(.system(size: 10))
                        Text(phase.rawValue)
                            .font(.system(.caption2, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(phaseColor(phase).opacity(0.1))
                    .foregroundStyle(phaseColor(phase))
                    .clipShape(Capsule())
                }
                
                // Emotion pill
                if engine.currentEmotion.confidence > 0.3 {
                    SentimentIndicator(emotion: engine.currentEmotion)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.02))
            
            Divider().padding(.horizontal, 8)
            
            // Content
            switch tab {
            case .commercial:
                if engine.commercialCoachEnabled {
                    CommercialCoachPanel()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else {
                    disabledMessage("Coach commercial désactivé", icon: "chart.line.uptrend.xyaxis")
                }
            case .empathie:
                if engine.sentimentEnabled && engine.coachingEnabled {
                    CoachingPanelView()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else {
                    disabledMessage("Coach empathique désactivé", icon: "brain.head.profile")
                }
            }
        }
    }
    
    func disabledMessage(_ text: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Text("Activer dans Réglages").font(.caption2).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
    
    func phaseColor(_ phase: SalesPhaseDetector.SalesPhase) -> Color {
        switch phase {
        case .ouverture: .cyan; case .decouverte: .blue; case .qualification: .indigo
        case .presentation: .purple; case .objections: .orange; case .closing: .green; case .suivi: .mint
        }
    }
}

// MARK: - Header Bar

struct HeaderBar: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @Binding var showHistory: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { showHistory.toggle() }) {
                Image(systemName: "sidebar.left").font(.system(size: 12))
            }.buttonStyle(.plain)
            
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            
            if engine.hotkeys.isEnabled {
                Text("⌥⇧R").font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.purple.opacity(0.15)).foregroundStyle(.purple).clipShape(Capsule())
            }
            if engine.systemAudio.isCapturing, let app = engine.systemAudio.selectedApp {
                Text("+ \(app.name)").font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.green.opacity(0.15)).foregroundStyle(.green).clipShape(Capsule())
            }
            
            Spacer()
            
            if let session = engine.currentSession {
                let me = session.segments.filter { $0.speaker == .me }.count
                let other = session.segments.filter { $0.speaker == .other }.count
                if other > 0 {
                    HStack(spacing: 4) { Text("🎤\(me)"); Text("🔊\(other)") }
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                }
                Image(systemName: "externaldrive.fill").font(.system(size: 8)).foregroundStyle(.green.opacity(0.6))
                Text(session.formattedDuration).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
    
    var statusColor: Color {
        switch engine.state {
        case .recording: .red; case .paused: .orange; case .ready: .green; case .loading: .yellow; case .idle: .gray
        }
    }
    var statusText: String {
        switch engine.state {
        case .recording: "● REC"; case .paused: "❚❚ PAUSE"; case .ready: "PRÊT"; case .loading: "CHARGEMENT..."; case .idle: "INACTIF"
        }
    }
}

// MARK: - App Selection Bar

struct AppSelectionBar: View {
    @EnvironmentObject var engine: TranscriptionEngine
    
    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $engine.captureSystemAudio) {
                Image(systemName: "speaker.wave.2").font(.system(size: 12))
            }.toggleStyle(.switch).controlSize(.mini)
            
            if engine.captureSystemAudio {
                if engine.systemAudio.availableApps.isEmpty {
                    Label("Aucune app de visio", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("", selection: Binding(
                        get: { engine.systemAudio.selectedApp },
                        set: { engine.systemAudio.selectedApp = $0 }
                    )) {
                        ForEach(engine.systemAudio.availableApps) { app in
                            Text("\(appIcon(app.name)) \(app.name)").tag(Optional(app))
                        }
                    }.pickerStyle(.menu).frame(maxWidth: 200)
                }
                Button(action: { Task { await engine.systemAudio.refreshAvailableApps() } }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(.plain)
            }
            
            Spacer()
            
            if engine.state == .recording { DualAudioLevels() }
        }
        .padding(.horizontal, 16).padding(.vertical, 6).background(Color.primary.opacity(0.02))
    }
    
    func appIcon(_ name: String) -> String {
        switch name {
        case "Zoom": "📹"; case "Microsoft Teams": "👥"
        case "Google Chrome", "Safari", "Firefox", "Arc": "🌐"
        case "Slack": "💬"; case "Discord": "🎮"; case "FaceTime": "📱"
        default: "🔊"
        }
    }
}

struct DualAudioLevels: View {
    @EnvironmentObject var engine: TranscriptionEngine
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "mic.fill").font(.system(size: 8)).foregroundStyle(.blue)
                AudioLevelBar(level: engine.micAudioLevel, color: .blue).frame(width: 30, height: 6)
            }
            if engine.captureSystemAudio && engine.systemAudio.isCapturing {
                HStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 8)).foregroundStyle(.green)
                    AudioLevelBar(level: engine.systemAudioLevel, color: .green).frame(width: 30, height: 6)
                }
            }
        }
    }
}

struct AudioLevelBar: View {
    let level: Float; var color: Color = .green
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > 0.8 ? .red : level > 0.5 ? .orange : color)
                    .frame(width: g.size.width * CGFloat(level))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
}

// MARK: - Transcription View

struct TranscriptionView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let session = engine.currentSession {
                        ForEach(session.segments) { seg in SegmentRow(segment: seg).id(seg.id) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if !engine.liveTextMic.isEmpty { LiveRow(text: engine.liveTextMic, icon: "mic.fill", color: .blue) }
                        if !engine.liveTextSystem.isEmpty { LiveRow(text: engine.liveTextSystem, icon: "speaker.wave.2.fill", color: .green) }
                    }.id("live")
                    
                    if engine.currentSession?.segments.isEmpty ?? true && engine.liveTextMic.isEmpty && engine.liveTextSystem.isEmpty {
                        EmptyTranscriptionView()
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: engine.currentSession?.segments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let id = engine.currentSession?.segments.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onChange(of: engine.liveTextMic) { _, _ in withAnimation { proxy.scrollTo("live", anchor: .bottom) } }
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
                Text(s.label.emoji).font(.system(size: 12))
                    .help("\(s.label.rawValue) (V:\(String(format: "%.1f", s.valence)) A:\(String(format: "%.1f", s.arousal)))")
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
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TypingDots(color: color).frame(width: 38, alignment: .trailing)
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color)
            Text(text).font(.body).foregroundStyle(.secondary).italic()
        }.padding(.horizontal, 16)
    }
}

struct TypingDots: View {
    var color: Color = .accentColor
    @State private var dot = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in Circle().fill(color).frame(width: 4, height: 4).opacity(i <= dot ? 1 : 0.3) }
        }.onReceive(timer) { _ in dot = (dot + 1) % 3 }
    }
}

struct EmptyTranscriptionView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile").font(.system(size: 48)).foregroundStyle(.quaternary)
            Text(engine.state == .recording ? "En écoute... VAD + Coaching actifs" : "Appuyez sur ● pour démarrer")
                .font(.title3).foregroundStyle(.secondary)
            if engine.state != .recording {
                VStack(spacing: 4) {
                    Text("⌥⇧R enregistrer • ⌥⇧S stop • ⌥⇧N nouvelle session")
                    Text("🎤 Micro + 🔊 Prospect + 🧠 Coach empathique + 📊 Coach commercial")
                }.font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }.frame(maxWidth: .infinity).padding(32)
    }
}

struct ModelLoadingView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if let error = engine.error {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                Text(error).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Réessayer") { Task { await engine.loadModel() } }.buttonStyle(.borderedProminent)
            } else {
                ProgressView().scaleEffect(1.5)
                Text("Chargement du modèle Whisper...").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
        }.frame(maxWidth: .infinity).padding(32)
    }
}

// MARK: - Control Bar

struct ControlBar: View {
    @EnvironmentObject var engine: TranscriptionEngine
    var body: some View {
        HStack(spacing: 16) {
            Button(action: { Task { await engine.toggleRecording() } }) {
                Image(systemName: engine.state == .recording ? "pause.circle.fill" : "record.circle")
                    .font(.system(size: 28)).foregroundStyle(engine.state == .recording ? .orange : .red)
            }.buttonStyle(.plain).keyboardShortcut("r", modifiers: .command).disabled(!engine.modelLoaded)
            
            Button(action: { Task { await engine.stopRecording() } }) {
                Image(systemName: "stop.circle.fill").font(.system(size: 28)).foregroundStyle(.primary.opacity(0.6))
            }.buttonStyle(.plain).keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(engine.state != .recording && engine.state != .paused)
            
            Spacer()
            if let c = engine.currentSession?.segments.count, c > 0 { Text("\(c) segments").font(.caption).foregroundStyle(.tertiary) }
            Spacer()
            
            Menu {
                ForEach(TranscriptionEngine.ExportFormat.allCases, id: \.self) { f in
                    Button(f.rawValue) { engine.saveSession(format: f) }
                }
            } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 16)) }
                .menuStyle(.borderlessButton).frame(width: 30)
                .disabled(engine.currentSession?.segments.isEmpty ?? true)
            
            Button(action: { Task { await engine.newSession() } }) {
                Image(systemName: "plus.circle").font(.system(size: 16))
            }.buttonStyle(.plain).keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Session History Sidebar

struct SessionHistoryView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    @Binding var showHistory: Bool
    @State private var sessions: [TranscriptionSession] = []
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Historique").font(.headline); Spacer()
                Text("\(engine.savedSessionCount)").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2)).clipShape(Capsule())
            }.padding(.horizontal, 12).padding(.vertical, 8)
            
            TextField("Rechercher...", text: $searchText)
                .textFieldStyle(.roundedBorder).controlSize(.small).padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { s in
                        SessionRowView(session: s).onTapGesture { engine.loadSavedSession(id: s.id) }
                    }
                    if filtered.isEmpty { Text("Aucune session").font(.caption).foregroundStyle(.tertiary).padding(.top, 20) }
                }.padding(.vertical, 4)
            }
        }
        .onAppear { refresh() }
        .onChange(of: engine.savedSessionCount) { _, _ in refresh() }
    }
    
    var filtered: [TranscriptionSession] {
        searchText.isEmpty ? sessions : sessions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    func refresh() { sessions = engine.savedSessions() }
}

struct SessionRowView: View {
    let session: TranscriptionSession
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title).font(.caption).fontWeight(.medium).lineLimit(1)
            HStack { Text(session.startDate.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(session.formattedDuration) }
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(hovered ? Color.accentColor.opacity(0.1) : .clear)
        .cornerRadius(4).onHover { hovered = $0 }
    }
}
