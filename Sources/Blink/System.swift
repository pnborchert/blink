import AppKit
import ApplicationServices
import BlinkCore
import os

let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "blink", category: "blink")

/// Thin wrappers around the CoreGraphics / AppKit calls Blink needs.
/// Everything here works in global Quartz coordinates (top-left origin).
enum SystemDisplays {
    /// Active, non-mirrored displays.
    static func current() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { Display(id: $0, frame: CGDisplayBounds($0)) }
    }

    /// The user-facing name ("Built-in Retina Display", "LG UltraFine", …).
    @MainActor
    static func name(of id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
        return screen?.localizedName ?? "Display \(id)"
    }

    /// Converts a Quartz point (top-left origin) to AppKit's coordinate space
    /// (bottom-left origin of the main display).
    static func cocoaPoint(fromQuartz p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: CGDisplayBounds(CGMainDisplayID()).height - p.y)
    }
}

@MainActor
enum Cursor {
    static var location: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// `CGWarpMouseCursorPosition` normally freezes the cursor for ~250 ms after
    /// a warp. Setting the suppression interval to zero removes that lag.
    private static let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()

    static func move(to point: CGPoint) {
        _ = eventSource // make sure the suppression interval is set
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        // A warp does not emit a mouse-moved event, so hover effects and cursor
        // shapes would only update on the next physical movement. With
        // Accessibility access we can post one ourselves.
        if Accessibility.isTrusted {
            CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking for Accessibility access, if not granted yet.
    static func requestIfNeeded() {
        guard !isTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

@MainActor
enum Alert {
    static func show(_ title: String, _ message: String) {
        log.error("\(title, privacy: .public): \(message, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
