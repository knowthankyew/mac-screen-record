import AppKit
import Carbon.HIToolbox
import OSLog

/// Actions that can be triggered via global keyboard shortcuts.
public enum HotkeyAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case startRecording
    case stopRecording
    case togglePause
    case toggleFacecam
    case toggleKeystrokes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .startRecording:   return "Start Recording"
        case .stopRecording:    return "Stop Recording"
        case .togglePause:      return "Pause / Resume Recording"
        case .toggleFacecam:    return "Toggle Facecam (PiP)"
        case .toggleKeystrokes: return "Toggle Keystroke Overlay"
        }
    }
}

/// A Carbon virtual keycode and modifier mask pairing.
public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public var keyCode: Int
    public var modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// User-facing string representation, e.g. "⌃⌥⌘R", "⌥Space".
    public var displayString: String {
        var result = ""
        if (modifiers & controlKey) != 0 { result += "⌃" }
        if (modifiers & optionKey)  != 0 { result += "⌥" }
        if (modifiers & shiftKey)   != 0 { result += "⇧" }
        if (modifiers & cmdKey)     != 0 { result += "⌘" }

        if let special = KeystrokeOverlayController.specialKeyGlyph(forKeyCode: keyCode) {
            result += special
        } else if let scalar = UnicodeScalar(keyCodeToAscii(keyCode: keyCode)), Character(scalar).isASCII {
            result += String(Character(scalar)).uppercased()
        } else {
            result += "Key(\(keyCode))"
        }
        return result
    }

    private func keyCodeToAscii(keyCode: Int) -> UInt32 {
        switch keyCode {
        case kVK_ANSI_A: return UInt32(Character("A").asciiValue!)
        case kVK_ANSI_B: return UInt32(Character("B").asciiValue!)
        case kVK_ANSI_C: return UInt32(Character("C").asciiValue!)
        case kVK_ANSI_D: return UInt32(Character("D").asciiValue!)
        case kVK_ANSI_E: return UInt32(Character("E").asciiValue!)
        case kVK_ANSI_F: return UInt32(Character("F").asciiValue!)
        case kVK_ANSI_G: return UInt32(Character("G").asciiValue!)
        case kVK_ANSI_H: return UInt32(Character("H").asciiValue!)
        case kVK_ANSI_I: return UInt32(Character("I").asciiValue!)
        case kVK_ANSI_J: return UInt32(Character("J").asciiValue!)
        case kVK_ANSI_K: return UInt32(Character("K").asciiValue!)
        case kVK_ANSI_L: return UInt32(Character("L").asciiValue!)
        case kVK_ANSI_M: return UInt32(Character("M").asciiValue!)
        case kVK_ANSI_N: return UInt32(Character("N").asciiValue!)
        case kVK_ANSI_O: return UInt32(Character("O").asciiValue!)
        case kVK_ANSI_P: return UInt32(Character("P").asciiValue!)
        case kVK_ANSI_Q: return UInt32(Character("Q").asciiValue!)
        case kVK_ANSI_R: return UInt32(Character("R").asciiValue!)
        case kVK_ANSI_S: return UInt32(Character("S").asciiValue!)
        case kVK_ANSI_T: return UInt32(Character("T").asciiValue!)
        case kVK_ANSI_U: return UInt32(Character("U").asciiValue!)
        case kVK_ANSI_V: return UInt32(Character("V").asciiValue!)
        case kVK_ANSI_W: return UInt32(Character("W").asciiValue!)
        case kVK_ANSI_X: return UInt32(Character("X").asciiValue!)
        case kVK_ANSI_Y: return UInt32(Character("Y").asciiValue!)
        case kVK_ANSI_Z: return UInt32(Character("Z").asciiValue!)
        default:         return 0
        }
    }

    /// Canonical system defaults for Phase 6 + Phase 8.
    public static func defaultBinding(for action: HotkeyAction) -> HotkeyBinding {
        let hyper = cmdKey | optionKey | controlKey
        switch action {
        case .startRecording:
            return HotkeyBinding(keyCode: kVK_ANSI_R, modifiers: hyper) // ⌃⌥⌘R
        case .stopRecording:
            return HotkeyBinding(keyCode: kVK_ANSI_S, modifiers: hyper) // ⌃⌥⌘S
        case .togglePause:
            return HotkeyBinding(keyCode: kVK_Space, modifiers: optionKey) // ⌥Space
        case .toggleFacecam:
            return HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey) // ⌃⌥P
        case .toggleKeystrokes:
            return HotkeyBinding(keyCode: kVK_ANSI_K, modifiers: controlKey | optionKey) // ⌃⌥K
        }
    }

    public static var defaultBindings: [HotkeyAction: HotkeyBinding] {
        var map: [HotkeyAction: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases {
            map[action] = defaultBinding(for: action)
        }
        return map
    }
}

/// A single Carbon-registered global hotkey. Carbon's `RegisterEventHotKey` is
/// the only no-permissions, system-level hotkey API on macOS — neither
/// Accessibility nor Input Monitoring is required.
public final class GlobalHotkey {
    public typealias Handler = () -> Void

    private let handler: Handler
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var hotKeyID = EventHotKeyID()

    /// `keyCode` is a Carbon virtual key code (e.g. `kVK_ANSI_R = 15`).
    /// `modifiers` is an OR of `cmdKey | shiftKey | optionKey | controlKey`.
    public init(keyCode: Int, modifiers: Int, handler: @escaping Handler) {
        self.handler = handler
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let h = eventHandler { RemoveEventHandler(h) }
        if let r = hotKeyRef    { UnregisterEventHotKey(r) }
    }

    private func register(keyCode: Int, modifiers: Int) {
        self.hotKeyID = EventHotKeyID(signature: 0x4D535263 /* "MSRc" */, id: UInt32.random(in: 1...UInt32.max))
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard regStatus == noErr else { return }
        self.hotKeyRef = ref

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, ptr -> OSStatus in
            guard let ptr, let event else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<GlobalHotkey>.fromOpaque(ptr).takeUnretainedValue()
            var pressed = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressed
            )
            guard err == noErr,
                  pressed.signature == me.hotKeyID.signature,
                  pressed.id == me.hotKeyID.id else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { [weak me] in me?.handler() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            userData,
            &eventHandler
        )
    }
}

/// High-level global hotkey manager supporting default and customizable actions.
@MainActor
public final class GlobalHotkeyController: ObservableObject {
    public typealias ActionHandler = @MainActor () -> Void

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "Hotkeys")
    private var registeredKeys: [HotkeyAction: GlobalHotkey] = [:]
    private var actionHandlers: [HotkeyAction: ActionHandler] = [:]
    private var currentBindings: [HotkeyAction: HotkeyBinding] = [:]

    public init() {}

    /// Legacy convenience installer preserving the original start/stop registration signature.
    public func install(start: @escaping @MainActor () -> Void,
                        stop:  @escaping @MainActor () -> Void) {
        let handlers: [HotkeyAction: ActionHandler] = [
            .startRecording: start,
            .stopRecording: stop
        ]
        self.install(bindings: HotkeyBinding.defaultBindings, handlers: handlers)
    }

    /// Installs the full suite of action handlers with user-configured or default bindings.
    public func install(
        bindings: [HotkeyAction: HotkeyBinding],
        handlers: [HotkeyAction: ActionHandler]
    ) {
        self.actionHandlers = handlers
        self.currentBindings = bindings
        rebuildAll()
        log.info("Universal global hotkeys installed: \(bindings.map { "\($0.key.rawValue)=\($0.value.displayString)" }.joined(separator: ", "), privacy: .public)")
    }

    /// Re-binds a specific action to a new key combination at runtime.
    public func updateBinding(for action: HotkeyAction, binding: HotkeyBinding) {
        currentBindings[action] = binding
        registeredKeys[action] = nil
        if let handler = actionHandlers[action] {
            registeredKeys[action] = GlobalHotkey(keyCode: binding.keyCode, modifiers: binding.modifiers) {
                Task { @MainActor in handler() }
            }
            log.info("Updated hotkey binding for \(action.rawValue, privacy: .public): \(binding.displayString, privacy: .public)")
        }
    }

    /// Updates all active bindings from a dictionary, rebuilding registrations.
    public func updateBindings(_ bindings: [HotkeyAction: HotkeyBinding]) {
        self.currentBindings = bindings
        rebuildAll()
        log.info("Universal global hotkeys reloaded with \(bindings.count, privacy: .public) bindings")
    }

    /// Rebuilds all active global hotkeys based on currentBindings and actionHandlers.
    public func rebuildAll() {
        registeredKeys.removeAll()
        for (action, handler) in actionHandlers {
            guard let binding = currentBindings[action] else { continue }
            registeredKeys[action] = GlobalHotkey(keyCode: binding.keyCode, modifiers: binding.modifiers) {
                Task { @MainActor in handler() }
            }
        }
    }

    public func uninstall() {
        registeredKeys.removeAll()
        actionHandlers.removeAll()
    }
}
