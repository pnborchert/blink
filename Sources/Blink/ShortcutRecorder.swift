import AppKit
import BlinkCore

/// A small window that captures the next key combination as the new switch
/// shortcut. Backward is always the same combination plus ⇧.
@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var monitor: Any?
    private var completion: ((Shortcut?) -> Void)?
    private let keysLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    private static let defaultMessage =
        "Blink backward is the same shortcut plus ⇧. Esc cancels."

    var isRecording: Bool { window != nil }

    /// Calls `completion` with the recorded shortcut, or nil if cancelled.
    func record(current: Shortcut?, completion: @escaping (Shortcut?) -> Void) {
        guard window == nil else { return }
        self.completion = completion

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blink Shortcut"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self

        let title = NSTextField(labelWithString: "Press the shortcut for blinking forward")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.alignment = .center

        keysLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        keysLabel.alignment = .center
        keysLabel.stringValue = current?.description ?? "…"
        keysLabel.textColor = .tertiaryLabelColor

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.stringValue = Self.defaultMessage

        let stack = NSStackView(views: [title, keysLabel, messageLabel])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        window.contentView = stack
        messageLabel.preferredMaxLayoutWidth = 340

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = Shortcut.Modifiers(event.modifierFlags)

        if event.type == .flagsChanged {
            keysLabel.textColor = .labelColor
            keysLabel.stringValue = modifiers.isEmpty ? "…" : modifiers.symbols
            return false
        }

        if event.keyCode == 0x35 && modifiers.isEmpty { // esc
            finish(nil)
            return true
        }
        guard !modifiers.subtracting(.shift).isEmpty else {
            showError("Include ⌥, ⌃ or ⌘ — a plain key would stop typing that key.")
            return true
        }
        guard !modifiers.contains(.shift) else {
            showError("⇧ is used for blinking backward. Press the shortcut without ⇧.")
            return true
        }
        guard let name = Self.keyName(for: event),
              let shortcut = try? Shortcut(key: name, modifiers: modifiers)
        else {
            showError("That key isn't supported. Try a letter, digit, Tab, Space, an arrow or an F-key.")
            return true
        }
        keysLabel.stringValue = shortcut.description
        finish(shortcut)
        return true
    }

    private func showError(_ message: String) {
        messageLabel.stringValue = message
        messageLabel.textColor = .systemRed
        NSSound.beep()
    }

    private func finish(_ shortcut: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let completion = self.completion
        self.completion = nil
        window?.delegate = nil
        window?.close()
        window = nil
        completion?(shortcut)
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    /// Config name of the pressed key: named keys by code, character keys by
    /// what they type in the current layout (ignoring ⌥, so ⌥A is "a", not "å").
    private static func keyName(for event: NSEvent) -> String? {
        if let name = Shortcut.specialKeyName(forKeyCode: UInt32(event.keyCode)) { return name }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 else { return nil }
        return chars
    }
}
