import BlinkCore
import Carbon.HIToolbox

/// Maps characters to the physical keys that type them in the active keyboard
/// layout, so `§`, `z` or `ö` hit the right key on ISO, QWERTZ, AZERTY, … boards.
@MainActor
enum KeyboardLayout {
    static let changedNotification = Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")

    private static var cache: [String: UInt32]?

    static func invalidate() { cache = nil }

    /// The key code to register for `shortcut`: character keys are looked up in
    /// the current layout, everything else (arrows, F-keys, …) is layout-independent.
    static func keyCode(for shortcut: Shortcut) -> UInt32 {
        guard shortcut.isCharacterKey else { return shortcut.keyCode }
        if cache == nil { cache = buildMap() }
        return cache?[shortcut.key] ?? shortcut.keyCode
    }

    private static func buildMap() -> [String: UInt32] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var map: [String: UInt32] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            // Lower codes first, so the main row wins over the keypad for digits.
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
                )
                guard status == noErr, length > 0 else { continue }
                let string = String(utf16CodeUnits: chars, count: length).lowercased()
                if map[string] == nil { map[string] = UInt32(code) }
            }
        }
        return map
    }
}
