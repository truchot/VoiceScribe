import AppKit
import SwiftUI
import Combine

/// Manages the floating overlay window lifecycle.
///
/// Responsibilities:
/// - Create/destroy the NSWindow
/// - Show/hide with animation
/// - Auto-show when recording starts (if enabled)
/// - Persist window position across launches
/// - Adapt height to content
@MainActor
final class OverlayManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isVisible = false
    @AppStorage("overlayAutoShow") var autoShowOnRecord = true
    @AppStorage("overlayPosition") private var savedPosition = ""
    @AppStorage("overlayOpacity") var overlayOpacity: Double = 0.95
    
    // MARK: - Private
    
    private var window: FloatingOverlayWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    
    // Stores (set during configure)
    private weak var recording: RecordingStore?
    private weak var coaching: CoachingStore?
    
    // MARK: - Configure
    
    /// Wire to stores. Call once at app startup.
    func configure(
        env: AppEnvironment,
        recording: RecordingStore,
        audio: AudioStore,
        transcription: TranscriptionStore,
        sentiment: SentimentStore,
        coaching: CoachingStore
    ) {
        self.recording = recording
        self.coaching = coaching
        
        // Build the SwiftUI content with all environment objects
        let content = CompactOverlayView()
            .environmentObject(env)
            .environmentObject(recording)
            .environmentObject(audio)
            .environmentObject(transcription)
            .environmentObject(sentiment)
            .environmentObject(coaching)
        
        // Create the hosting view (reusable — window is created on demand)
        hostingView = NSHostingView(rootView: AnyView(content))
        
        // Auto-show on recording start
        recording.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if state == .recording && self.autoShowOnRecord && !self.isVisible {
                    self.show()
                }
                if state == .ready && self.isVisible {
                    // Optional: auto-hide when recording stops
                    // Uncomment if desired:
                    // self.hide()
                }
            }
            .store(in: &cancellables)
        
        // Adapt height when coaching output changes
        coaching.$coachingOutput
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.adaptHeight()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Show / Hide
    
    func show() {
        guard !isVisible else { return }
        
        if window == nil {
            createWindow()
        }
        
        window?.alphaValue = 0
        window?.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = CGFloat(overlayOpacity)
        }
        
        isVisible = true
    }
    
    func hide() {
        guard isVisible, let window else { return }
        
        // Save position before hiding
        savePosition()
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.isVisible = false
        })
    }
    
    func toggle() {
        if isVisible { hide() } else { show() }
    }
    
    // MARK: - Window Creation
    
    private func createWindow() {
        let config = FloatingOverlayWindow.Config(
            width: 320,
            minHeight: 100,
            maxHeight: 420,
            cornerRadius: 12,
            opacity: CGFloat(overlayOpacity)
        )
        
        let win = FloatingOverlayWindow(config: config)
        
        if let hostingView {
            hostingView.frame = win.contentView?.bounds ?? .zero
            hostingView.autoresizingMask = [.width, .height]
            win.contentView?.addSubview(hostingView)
        }
        
        // Restore saved position
        restorePosition(window: win)
        
        window = win
    }
    
    // MARK: - Height Adaptation
    
    private func adaptHeight() {
        guard let window, let hostingView, isVisible else { return }
        
        // Ask SwiftUI for its ideal size
        let fittingSize = hostingView.fittingSize
        let targetHeight = min(420, max(100, fittingSize.height))
        
        if abs(window.frame.height - targetHeight) > 5 {
            window.updateHeight(targetHeight)
        }
    }
    
    // MARK: - Position Persistence
    
    private func savePosition() {
        guard let window else { return }
        let f = window.frame
        savedPosition = "\(f.origin.x),\(f.origin.y),\(f.size.width),\(f.size.height)"
    }
    
    private func restorePosition(window: FloatingOverlayWindow) {
        let parts = savedPosition.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else {
            // Default: top right
            window.positionAt(.topRight)
            return
        }
        
        let origin = NSPoint(x: parts[0], y: parts[1])
        let size = NSSize(width: parts[2], height: parts[3])
        let frame = NSRect(origin: origin, size: size)
        
        // Validate frame is on a visible screen
        let screens = NSScreen.screens
        let isOnScreen = screens.contains { $0.visibleFrame.intersects(frame) }
        
        if isOnScreen {
            window.setFrame(frame, display: true)
        } else {
            window.positionAt(.topRight)
        }
    }
    
    // MARK: - Cleanup
    
    func teardown() {
        savePosition()
        window?.orderOut(nil)
        window = nil
        hostingView = nil
        cancellables.removeAll()
    }
}
