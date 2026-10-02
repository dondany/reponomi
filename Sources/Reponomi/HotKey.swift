import AppKit
import Carbon.HIToolbox
import ReponomiCore

/// A system-wide shortcut. Uses Carbon hot keys, which need no Accessibility
/// or Input Monitoring permission.
final class HotKey {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Replaces the current shortcut. Returns false when the system refuses
    /// it, typically because another app already owns the combination.
    @discardableResult
    func register(_ spec: HotkeySpec) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x5250_4E4D), id: 1) // "RPNM"
        return RegisterEventHotKey(spec.keyCode, spec.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

extension HotkeySpec {
    private static let keyNames: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// The shortcut a key press describes, or nil when it lacks a ⌘, ⌃ or ⌥
    /// modifier and so would hijack ordinary typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        guard let key = Self.keyNames[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else {
            return nil
        }

        var modifiers = 0
        var display = ""
        if flags.contains(.control) { modifiers |= controlKey; display += "⌃" }
        if flags.contains(.option) { modifiers |= optionKey; display += "⌥" }
        if flags.contains(.shift) { modifiers |= shiftKey; display += "⇧" }
        if flags.contains(.command) { modifiers |= cmdKey; display += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers), display: display + key)
    }
}
