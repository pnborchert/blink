import AppKit
import ApplicationServices
import BlinkCore

/// A regular app window as reported by the window server.
struct WindowInfo {
    let pid: pid_t
    let frame: CGRect // Quartz coordinates
}

enum Windows {
    /// On-screen, normal-level app windows, front to back.
    ///
    /// Reading bounds and owner PIDs needs no permission (only window titles
    /// would require Screen Recording access, and we don't use them).
    static func onScreen() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return list.compactMap { info in
            guard
                (info[kCGWindowLayer as String] as? Int) == 0,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                frame.width >= 50, frame.height >= 50
            else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            return WindowInfo(pid: pid, frame: frame)
        }
    }

    /// The frontmost window whose center lies on `display`.
    static func frontmost(on display: Display) -> WindowInfo? {
        onScreen().first { display.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }

    /// Raises `window` and makes its app frontmost so it receives keyboard input.
    ///
    /// Raising one specific window needs the Accessibility API. Without access
    /// we can only activate the app, which focuses whichever window the app
    /// considers main — possibly on another screen — so we skip it in that case.
    @MainActor
    static func focus(_ window: WindowInfo) {
        guard Accessibility.isTrusted else { return }

        let app = AXUIElementCreateApplication(window.pid)
        // Don't let a hung app stall the hotkey.
        AXUIElementSetMessagingTimeout(app, 0.25)

        // If we can't pin down the exact window, activating the app would focus
        // its main window, which may be on the screen we just left.
        guard let axWindow = axWindow(of: app, matching: window.frame) else { return }
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        // Setting AXFrontmost works even though Blink itself is a background app,
        // where NSRunningApplication.activate() may be refused (macOS 14+
        // cooperative activation). Keep activate() as a fallback.
        let result = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if result != .success {
            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        }
    }

    /// Finds the AX window whose frame matches the window server's frame.
    private static func axWindow(of app: AXUIElement, matching frame: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }

        return windows.first { element in
            guard let f = axFrame(of: element) else { return false }
            return abs(f.minX - frame.minX) <= 2 && abs(f.minY - frame.minY) <= 2
                && abs(f.width - frame.width) <= 2 && abs(f.height - frame.height) <= 2
        }
    }

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
