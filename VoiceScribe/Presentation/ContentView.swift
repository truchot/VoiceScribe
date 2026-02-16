import SwiftUI

/// Main content view — thin shell that composes extracted sub-views.
///
/// Each sub-view only observes the stores it needs:
/// - HeaderBar: recording, sentiment, coaching, transcription, env, overlay
/// - AppSelectionBar: audio, recording
/// - CoachingPanel: coaching, sentiment
/// - TranscriptionView: transcription
/// - ControlBar: env, recording, transcription, coaching
/// - SessionHistoryView: transcription
///
/// This means: a sentiment update does NOT re-render TranscriptionView,
/// a new segment does NOT re-render CoachingPanel, etc.
struct ContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var recording: RecordingStore
    @EnvironmentObject var audio: AudioStore
    @EnvironmentObject var sentiment: SentimentStore
    @EnvironmentObject var coaching: CoachingStore
    @State private var showHistory = false
    
    var body: some View {
        HStack(spacing: 0) {
            if showHistory {
                SessionHistoryView(showHistory: $showHistory).frame(width: 200)
                    .transition(.move(edge: .leading))
                Divider()
            }
            VStack(spacing: 0) {
                HeaderBar(showHistory: $showHistory)
                Divider()
                
                if recording.modelLoaded {
                    if audio.systemCaptureAvailable { AppSelectionBar(); Divider() }
                    
                    // Coaching panel (when recording with system audio)
                    if recording.state == .recording && audio.captureSystemAudio && coaching.coachingEnabled {
                        CoachingPanel()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        Divider()
                    }
                    
                    // Sentiment mini-bar (when coaching is off but sentiment is on)
                    if recording.state == .recording && sentiment.sentimentEnabled && !coaching.coachingEnabled {
                        if sentiment.currentEmotion.confidence > CoachingThresholds.emotionMinConfidence {
                            SentimentIndicator(emotion: sentiment.currentEmotion)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                            Divider()
                        }
                    }
                    
                    TranscriptionView()
                } else {
                    ModelLoadingView()
                }
                
                Divider()
                ControlBar()
            }
        }
        .frame(width: showHistory ? 760 : 580, height: 700)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: showHistory)
        .overlay(alignment: .top) {
            if let shift = sentiment.lastSentimentShift, recording.state == .recording {
                SentimentShiftBanner(from: shift.from, to: shift.to)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { sentiment.dismissShift() }
                        }
                    }
            }
        }
        .onAppear { Task { await env.loadModel() } }
    }
}
