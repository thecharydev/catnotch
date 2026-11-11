import Carbon.HIToolbox
import os

private let shortcutLogger = Logger(subsystem: "com.thecharydev.catnotch", category: "shortcut")

/// A system wide shortcut. Carbon hot keys need no Accessibility permission.
@MainActor
final class GlobalShortcut {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var installed = false
    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// `modifiers` + `key` runs `action` (Cmd+Option by default); `id` tells the hot keys apart. If another app already
    /// owns it, this only logs a warning. Dropping the key with `unregister()` gives it back to the app in front.
    init(id: UInt32, key: Int, modifiers: Int = cmdKey | optionKey, name: String, action: @escaping () -> Void) {
        self.id = id
        Self.actions[id] = action
        if !Self.installed {
            Self.installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hot = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hot)
                MainActor.assumeIsolated { GlobalShortcut.actions[hot.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }

        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers),
                                         EventHotKeyID(signature: OSType(0x434E5348) /* CNSH */, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            shortcutLogger.warning("Shortcut \(name, privacy: .public) could not be registered (status: \(status, privacy: .public)); it does nothing this launch")
        }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.actions[id] = nil
    }
}
