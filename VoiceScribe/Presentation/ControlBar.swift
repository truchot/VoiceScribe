import SwiftUI

/// Bottom bar: record/stop/pause, segment count, export, new session.
struct ControlBar: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var recording: RecordingStore
    @EnvironmentObject var transcription: TranscriptionStore
    @EnvironmentObject var coaching: CoachingStore
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: { Task { await env.toggleRecording() } }) {
                Image(systemName: recording.state == .recording ? "pause.circle.fill" : "record.circle")
                    .font(.system(size: 28)).foregroundStyle(recording.state == .recording ? .orange : .red)
            }.buttonStyle(.plain).keyboardShortcut("r", modifiers: .command).disabled(!recording.modelLoaded)
            
            Button(action: { Task { await env.stopRecording() } }) {
                Image(systemName: "stop.circle.fill").font(.system(size: 28)).foregroundStyle(.primary.opacity(0.6))
            }.buttonStyle(.plain).disabled(!recording.state.isActive)
            
            Spacer()
            if let c = transcription.currentSession?.segments.count, c > 0 { Text("\(c) segments").font(.caption).foregroundStyle(.tertiary) }
            Spacer()
            
            // Export menu
            Menu {
                ForEach(TranscriptionStore.ExportFormat.allCases, id: \.self) { f in
                    Button(f.rawValue) {
                        let report = f == .report ? coaching.generateReport() : nil
                        transcription.saveSession(format: f, report: report)
                    }
                }
            } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 16)) }
                .menuStyle(.borderlessButton).frame(width: 30)
                .disabled(transcription.currentSession?.segments.isEmpty ?? true)
            
            Button(action: { Task { await env.newSession() } }) {
                Image(systemName: "plus.circle").font(.system(size: 16))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
