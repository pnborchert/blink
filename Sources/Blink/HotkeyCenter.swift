import BlinkCore
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon's `RegisterEventHotKey`.
///
/// This is still the lightest way to get global shortcuts on macOS: it needs no
/// Accessibility or Input Monitoring permission, and the key press is consumed
/// (it does not leak into the frontmost app).
///
/// Several centers can coexist (Blink uses one for permanent shortcuts and one
/// for keys that are only live while switching); IDs are unique across them.
@MainActor
final class HotkeyCenter {
    private static let signature: OSType = 0x424C_4E4B // 'BLNK'

    private var registered: [UInt32: (ref: EventHotKeyRef, handler: () -> Void)] = [:]
    private static var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotkeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon delivers hotkey events on the main run loop.
                let id = hotKeyID.id
                return MainActor.assumeIsolated {
                    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                    // Not ours: let the next center's handler see it.
                    guard let handler = center.registered[id]?.handler else { return OSStatus(eventNotHandledErr) }
                    handler()
                    return noErr
                }
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr { log.error("InstallEventHandler failed: \(status)") }
    }

    /// Returns false if the shortcut could not be registered (usually because
    /// another app or the system already owns it).
    @discardableResult
    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        let id = Self.nextID
        Self.nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            KeyboardLayout.keyCode(for: shortcut),
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed for \(shortcut.description, privacy: .public): \(status)")
            return false
        }
        registered[id] = (ref, handler)
        return true
    }

    func unregisterAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }
}
