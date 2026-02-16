import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var engine: TranscriptionEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(engine.state == .recording ? .red : engine.state == .ready ? .green : .gray)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .font(.system(.caption, weight: .medium))
                
                Spacer()
                
                // Live sentiment in menu bar
                if engine.state == .recording && engine.currentEmotion.confidence > 0.2 {
                    Text(engine.currentEmotion.label.emoji)
                        .font(.system(size: 14))
                }
                
                if let session = engine.currentSession {
                    Text(session.formattedDuration)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Source info
            if engine.state == .recording {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill").font(.system(size: 9))
                    Text("Micro")
                        .font(.caption)
                    
                    if engine.captureSystemAudio, let app = engine.systemAudio.selectedApp {
                        Text("+").foregroundStyle(.tertiary)
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                        Text(app.name).font(.caption)
                    }
                    
                    if engine.sentimentEnabled {
                        Text("+").foregroundStyle(.tertiary)
                        Image(systemName: "brain.head.profile").font(.system(size: 9)).foregroundStyle(.purple)
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            // Sentiment shift notification
            if let shift = engine.lastSentimentShift {
                HStack(spacing: 4) {
                    Text(shift.from.emoji)
                    Image(systemName: "arrow.right").font(.system(size: 8))
                    Text(shift.to.emoji)
                    Text(shift.to.rawValue)
                        .font(.caption2)
                        .foregroundStyle(shift.to.color)
                }
                .padding(.vertical, 2)
            }
            
            Divider()
            
            // Controls
            Button(action: { Task { await engine.toggleRecording() } }) {
                Label(
                    engine.state == .recording ? "Pause" : "Enregistrer",
                    systemImage: engine.state == .recording ? "pause.fill" : "record.circle"
                )
            }
            .disabled(!engine.modelLoaded)
            
            Button(action: { Task { await engine.stopRecording() } }) {
                Label("Arrêter", systemImage: "stop.fill")
            }
            .disabled(engine.state != .recording && engine.state != .paused)
            
            Button(action: { Task { await engine.newSession() } }) {
                Label("Nouvelle session", systemImage: "plus")
            }
            
            Divider()
            
            // System audio toggle
            if engine.systemCaptureAvailable {
                Toggle(isOn: $engine.captureSystemAudio) {
                    Label("Audio système", systemImage: "speaker.wave.2")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                Toggle(isOn: $engine.sentimentEnabled) {
                    Label("Analyse sentiment", systemImage: "brain.head.profile")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                if engine.captureSystemAudio {
                    ForEach(engine.systemAudio.availableApps) { app in
                        Button(action: { engine.systemAudio.selectedApp = app }) {
                            HStack {
                                Text(app.name).font(.caption)
                                Spacer()
                                if engine.systemAudio.selectedApp?.id == app.id {
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
                Text("\(engine.savedSessionCount) sessions sauvegardées")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 260)
    }
    
    var statusText: String {
        switch engine.state {
        case .recording: return "Enregistrement"
        case .paused: return "En pause"
        case .ready: return "Prêt"
        case .loading: return "Chargement..."
        case .idle: return "Inactif"
        }
    }
}
