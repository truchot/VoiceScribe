import SwiftUI
import AVFoundation

@main
struct VoiceScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var env = AppEnvironment()
    
    var body: some Scene {
        Window("VoiceScribe", id: "main") {
            ContentView()
                .environmentObject(env)
                .environmentObject(env.recording)
                .environmentObject(env.audio)
                .environmentObject(env.transcription)
                .environmentObject(env.sentiment)
                .environmentObject(env.coaching)
                .environmentObject(env.summary)
                .environmentObject(env.overlay)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        
        Settings {
            SettingsView()
                .environmentObject(env)
                .environmentObject(env.recording)
                .environmentObject(env.audio)
                .environmentObject(env.transcription)
                .environmentObject(env.sentiment)
                .environmentObject(env.coaching)
                .environmentObject(env.summary)
                .environmentObject(env.overlay)
        }
        
        MenuBarExtra("VoiceScribe", systemImage: "waveform.circle.fill") {
            MenuBarView()
                .environmentObject(env)
                .environmentObject(env.recording)
                .environmentObject(env.audio)
                .environmentObject(env.transcription)
                .environmentObject(env.sentiment)
                .environmentObject(env.coaching)
                .environmentObject(env.summary)
                .environmentObject(env.overlay)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { Log.audio.warning("Microphone access denied") }
        }
    }
}
