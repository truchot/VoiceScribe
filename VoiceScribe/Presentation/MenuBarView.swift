import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var recording: RecordingStore
    @EnvironmentObject var audio: AudioStore
    @EnvironmentObject var transcription: TranscriptionStore
    @EnvironmentObject var sentiment: SentimentStore
    @EnvironmentObject var overlay: OverlayManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(recording.state.statusColor)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .font(.system(.caption, weight: .medium))
                
                Spacer()
                
                if recording.state == .recording && sentiment.currentEmotion.confidence > 0.2 {
                    Text(sentiment.currentEmotion.label.emoji)
                        .font(.system(size: 14))
                }
                
                if let session = transcription.currentSession {
                    Text(session.formattedDuration)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Source info
            if recording.state == .recording {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill").font(.system(size: 9))
                    Text("Micro").font(.caption)
                    
                    if audio.captureSystemAudio, let app = audio.systemAudio.selectedApp {
                        Text("+").foregroundStyle(.tertiary)
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                        Text(app.name).font(.caption)
                    }
                    
                    if sentiment.sentimentEnabled {
                        Text("+").foregroundStyle(.tertiary)
                        Image(systemName: "brain.head.profile").font(.system(size: 9)).foregroundStyle(.purple)
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            // Sentiment shift
            if let shift = sentiment.lastSentimentShift {
                HStack(spacing: 4) {
                    Text(shift.from.emoji)
                    Image(systemName: "arrow.right").font(.system(size: 8))
                    Text(shift.to.emoji)
                    Text(shift.to.rawValue).font(.caption2).foregroundStyle(shift.to.color)
                }
                .padding(.vertical, 2)
            }
            
            Divider()
            
            // Controls
            Button(action: { Task { await env.toggleRecording() } }) {
                Label(
                    recording.state == .recording ? "Pause" : "Enregistrer",
                    systemImage: recording.state == .recording ? "pause.fill" : "record.circle"
                )
            }
            .disabled(!recording.modelLoaded)
            
            Button(action: { Task { await env.stopRecording() } }) {
                Label("Arrêter", systemImage: "stop.fill")
            }
            .disabled(!recording.state.isActive)
            
            Button(action: { Task { await env.newSession() } }) {
                Label("Nouvelle session", systemImage: "plus")
            }
            
            Divider()
            
            // Overlay toggle
            Button(action: { env.toggleOverlay() }) {
                Label(
                    overlay.isVisible ? "Masquer overlay" : "Afficher overlay",
                    systemImage: overlay.isVisible ? "pip.exit" : "pip.enter"
                )
            }
            
            Toggle(isOn: $overlay.autoShowOnRecord) {
                Label("Auto-overlay en enregistrement", systemImage: "rectangle.on.rectangle")
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            
            Divider()
            
            // System audio toggles
            if audio.systemCaptureAvailable {
                Toggle(isOn: $audio.captureSystemAudio) {
                    Label("Audio système", systemImage: "speaker.wave.2")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                Toggle(isOn: $sentiment.sentimentEnabled) {
                    Label("Analyse sentiment", systemImage: "brain.head.profile")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                if audio.captureSystemAudio {
                    ForEach(audio.systemAudio.availableApps) { app in
                        Button(action: { audio.systemAudio.selectedApp = app }) {
                            HStack {
                                Text(app.name).font(.caption)
                                Spacer()
                                if audio.systemAudio.selectedApp?.id == app.id {
                                    Image(systemName: "checkmark").font(.system(size: 10))
                                }
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Stats
            HStack {
                Text("\(transcription.savedSessionCount) sessions sauvegardées")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 280)
    }
    
    var statusText: String {
        switch recording.state {
        case .recording: "Enregistrement"
        case .paused: "En pause"
        case .ready: "Prêt"
        case .loading: "Chargement..."
        case .idle: "Inactif"
        }
    }
}
