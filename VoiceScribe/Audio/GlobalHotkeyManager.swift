import Foundation
import Carbon
import Cocoa
import Combine

/// Manages global keyboard shortcuts that work even when VoiceScribe doesn't have focus.
///
/// This is essential for real usage — you need to start/stop recording
/// while Zoom/Teams/Chrome has focus.
///
/// Uses Carbon Event API (the only reliable way for global hotkeys on macOS).
/// Requires Accessibility permission.
final class GlobalHotkeyManager: ObservableObject {
    
    // MARK: - Configuration
    
    struct Hotkey: Equatable, Codable {
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
        
        /// Default hotkeys
        static let toggleRecording = Hotkey(
            keyCode: UInt32(kVK_ANSI_R),      // R
            modifiers: UInt32(optionKey | shiftKey),  // ⌥⇧R
            label: "⌥⇧R"
        )
        
        static let stopRecording = Hotkey(
            keyCode: UInt32(kVK_ANSI_S),      // S
            modifiers: UInt32(optionKey | shiftKey),  // ⌥⇧S
            label: "⌥⇧S"
        )
        
        static let newSession = Hotkey(
            keyCode: UInt32(kVK_ANSI_N),      // N
            modifiers: UInt32(optionKey | shiftKey),  // ⌥⇧N
            label: "⌥⇧N"
        )
    }
    
    // MARK: - Published State
    
    @Published var isEnabled = false
    @Published var accessibilityGranted = false
    
    // MARK: - Callbacks
    
    var onToggleRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onNewSession: (() -> Void)?
    
    // MARK: - Private
    
    private var hotkeys: [EventHotKeyID: Hotkey] = [:]
    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    
    // Singleton-ish pattern for the C callback
    private static var shared: GlobalHotkeyManager?
    
    // MARK: - Init
    
    init() {
        GlobalHotkeyManager.shared = self
        checkAccessibility()
    }
    
    deinit {
        disable()
        GlobalHotkeyManager.shared = nil
    }
    
    // MARK: - Accessibility Check
    
    func checkAccessibility() {
        // Check if we have accessibility access (needed for global events)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        
        if accessibilityGranted {
            print("✅ Accessibility permission granted")
        } else {
            print("⚠️ Accessibility permission needed for global hotkeys")
        }
    }
    
    // MARK: - Enable / Disable
    
    func enable() {
        guard accessibilityGranted else {
            checkAccessibility()
            return
        }
        
        guard !isEnabled else { return }
        
        // Install Carbon event handler
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            
            guard status == noErr else { return status }
            
            DispatchQueue.main.async {
                GlobalHotkeyManager.shared?.handleHotkey(id: hotkeyID.id)
            }
            
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            nil,
            &eventHandler
        )
        
        // Register hotkeys
        registerHotkey(.toggleRecording, id: 1)
        registerHotkey(.stopRecording, id: 2)
        registerHotkey(.newSession, id: 3)
        
        isEnabled = true
        print("⌨️ Global hotkeys enabled")
    }
    
    func disable() {
        // Unregister all hotkeys
        for ref in hotkeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeyRefs.removeAll()
        hotkeys.removeAll()
        
        // Remove event handler
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        
        isEnabled = false
        print("⌨️ Global hotkeys disabled")
    }
    
    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }
    
    // MARK: - Private
    
    private func registerHotkey(_ hotkey: Hotkey, id: UInt32) {
        var hotkeyID = EventHotKeyID(signature: OSType(0x5653), id: id)  // 'VS' signature
        var hotkeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if status == noErr {
            hotkeyRefs.append(hotkeyRef)
            hotkeys[hotkeyID] = hotkey
            print("⌨️ Registered: \(hotkey.label)")
        } else {
            print("❌ Failed to register hotkey \(hotkey.label): \(status)")
        }
    }
    
    private func handleHotkey(id: UInt32) {
        switch id {
        case 1:
            print("⌨️ Global: Toggle Recording")
            onToggleRecording?()
        case 2:
            print("⌨️ Global: Stop Recording")
            onStopRecording?()
        case 3:
            print("⌨️ Global: New Session")
            onNewSession?()
        default:
            break
        }
    }
}

// MARK: - EventHotKeyID Hashable

extension EventHotKeyID: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(signature)
        hasher.combine(id)
    }
    
    public static func == (lhs: EventHotKeyID, rhs: EventHotKeyID) -> Bool {
        lhs.signature == rhs.signature && lhs.id == rhs.id
    }
}
