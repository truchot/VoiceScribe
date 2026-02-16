import AppKit
import SwiftUI

/// A frameless, always-on-top window for the compact coaching overlay.
///
/// Design constraints:
/// - Must stay visible over Zoom/Teams/Chrome fullscreen
/// - Must be draggable by clicking anywhere on the window
/// - Must not steal focus from the video call app
/// - Must be semi-transparent so it doesn't block content
/// - Must snap to screen edges for easy positioning
final class FloatingOverlayWindow: NSWindow {
    
    // MARK: - Configuration
    
    struct Config {
        var width: CGFloat = 320
        var minHeight: CGFloat = 120
        var maxHeight: CGFloat = 400
        var cornerRadius: CGFloat = 12
        var opacity: CGFloat = 0.95
        var defaultPosition: Position = .topRight
        var snapMargin: CGFloat = 12
        
        enum Position {
            case topRight, topLeft, bottomRight, bottomLeft
        }
    }
    
    private let config: Config
    
    // MARK: - Init
    
    init(config: Config = Config()) {
        self.config = config
        
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = NSRect(
            x: 0, y: 0,
            width: config.width,
            height: config.minHeight
        )
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Always on top — above fullscreen apps
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        // Transparent & rounded
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        
        // Don't steal focus
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        
        // Draggable
        isMovableByWindowBackground = true
        
        // Initial position
        positionAt(config.defaultPosition, on: screen)
    }
    
    // MARK: - Can become key (for clicks) but not main
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    // MARK: - Positioning
    
    func positionAt(_ position: Config.Position, on screen: NSScreen? = nil) {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let m = config.snapMargin
        
        let origin: NSPoint
        switch position {
        case .topRight:
            origin = NSPoint(
                x: visibleFrame.maxX - frame.width - m,
                y: visibleFrame.maxY - frame.height - m
            )
        case .topLeft:
            origin = NSPoint(
                x: visibleFrame.minX + m,
                y: visibleFrame.maxY - frame.height - m
            )
        case .bottomRight:
            origin = NSPoint(
                x: visibleFrame.maxX - frame.width - m,
                y: visibleFrame.minY + m
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visibleFrame.minX + m,
                y: visibleFrame.minY + m
            )
        }
        
        setFrameOrigin(origin)
    }
    
    /// Resize height smoothly to fit content.
    func updateHeight(_ newHeight: CGFloat) {
        let clamped = min(config.maxHeight, max(config.minHeight, newHeight))
        let currentFrame = frame
        // Keep top edge fixed, grow downward
        let newOrigin = NSPoint(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - clamped
        )
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: config.width, height: clamped))
        setFrame(newFrame, display: true, animate: true)
    }
    
    /// Snap to nearest screen edge after drag.
    func snapToEdge() {
        guard let screen = screen ?? NSScreen.main else { return }
        let vis = screen.visibleFrame
        let m = config.snapMargin
        
        var newOrigin = frame.origin
        
        // Snap X
        let distLeft = abs(frame.minX - vis.minX)
        let distRight = abs(vis.maxX - frame.maxX)
        if distLeft < 50 { newOrigin.x = vis.minX + m }
        else if distRight < 50 { newOrigin.x = vis.maxX - frame.width - m }
        
        // Snap Y
        let distTop = abs(vis.maxY - frame.maxY)
        let distBottom = abs(frame.minY - vis.minY)
        if distTop < 50 { newOrigin.y = vis.maxY - frame.height - m }
        else if distBottom < 50 { newOrigin.y = vis.minY + m }
        
        if newOrigin != frame.origin {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrameOrigin(newOrigin)
            }
        }
    }
    
    // MARK: - Mouse events for snap-on-release
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        snapToEdge()
    }
}
