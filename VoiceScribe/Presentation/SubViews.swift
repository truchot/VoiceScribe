import SwiftUI

// MARK: - App Selection Bar

struct AppSelectionBar: View {
    @EnvironmentObject var audio: AudioStore
    @EnvironmentObject var recording: RecordingStore
    
    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $audio.captureSystemAudio) {
                Image(systemName: "speaker.wave.2").font(.system(size: 12))
            }.toggleStyle(.switch).controlSize(.mini)
            
            if audio.captureSystemAudio {
                if audio.systemAudio.availableApps.isEmpty {
                    Label("Aucune app de visio", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("", selection: Binding(
                        get: { audio.systemAudio.selectedApp },
                        set: { audio.systemAudio.selectedApp = $0 }
                    )) {
                        ForEach(audio.systemAudio.availableApps) { app in
                            Text("\(appIcon(app.name)) \(app.name)").tag(Optional(app))
                        }
                    }.pickerStyle(.menu).frame(maxWidth: 200)
                }
                Button(action: { Task { await audio.refreshApps() } }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(.plain)
            }
            Spacer()
            if recording.state == .recording { DualAudioLevels() }
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

// MARK: - Audio Levels

struct DualAudioLevels: View {
    @EnvironmentObject var audio: AudioStore
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "mic.fill").font(.system(size: 8)).foregroundStyle(.blue)
                AudioLevelBar(level: audio.micAudioLevel, color: .blue).frame(width: 30, height: 6)
            }
            if audio.captureSystemAudio && audio.systemAudio.isCapturing {
                HStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 8)).foregroundStyle(.green)
                    AudioLevelBar(level: audio.systemAudioLevel, color: .green).frame(width: 30, height: 6)
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

// MARK: - Model Loading

struct ModelLoadingView: View {
    @EnvironmentObject var recording: RecordingStore
    @EnvironmentObject var env: AppEnvironment
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if let error = recording.error {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                Text(error).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Réessayer") { Task { await env.loadModel() } }.buttonStyle(.borderedProminent)
            } else {
                ProgressView().scaleEffect(1.5)
                Text("Chargement du modèle Whisper...").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
        }.frame(maxWidth: .infinity).padding(32)
    }
}

// MARK: - Session History

struct SessionHistoryView: View {
    @EnvironmentObject var transcription: TranscriptionStore
    @Binding var showHistory: Bool
    @State private var sessions: [TranscriptionSession] = []
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Historique").font(.headline); Spacer()
                Text("\(transcription.savedSessionCount)").font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2)).clipShape(Capsule())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            TextField("Rechercher...", text: $searchText).textFieldStyle(.roundedBorder).controlSize(.small).padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { s in
                        SessionRowView(session: s).onTapGesture { transcription.loadSavedSession(id: s.id) }
                    }
                }.padding(.vertical, 4)
            }
        }
        .onAppear { sessions = transcription.savedSessions() }
    }
    var filtered: [TranscriptionSession] { searchText.isEmpty ? sessions : sessions.filter { $0.title.localizedCaseInsensitiveContains(searchText) } }
}

struct SessionRowView: View {
    let session: TranscriptionSession
    @State private var hovered = false
    private var hasReport: Bool { SessionPersistence.shared.loadReport(sessionId: session.id) != nil }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.title).font(.caption).fontWeight(.medium).lineLimit(1)
                Spacer()
                if hasReport {
                    Image(systemName: "doc.text.fill").font(.system(size: 8)).foregroundStyle(.green)
                        .help("Rapport coaching disponible")
                }
            }
            HStack { Text(session.startDate.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(session.formattedDuration) }.font(.caption2).foregroundStyle(.tertiary)
        }.padding(.horizontal, 12).padding(.vertical, 6).background(hovered ? Color.accentColor.opacity(0.1) : .clear).cornerRadius(4).onHover { hovered = $0 }
    }
}

// SentimentIndicator and SentimentShiftBanner are in SentimentOverlayView.swift
// CoachingPanel is in CoachingPanelView.swift
