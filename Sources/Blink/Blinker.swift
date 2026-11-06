import AppKit
import BlinkCore

/// Executes blink actions with ⌘Tab-like semantics:
///
/// 1. A key press starts a *session*: the cursor moves immediately (with a
///    highlight ring), and the session-only keys (arrows, 1–9, esc) go live.
/// 2. Further presses while the modifier is held keep moving the cursor.
///    If enabled, holding longer than a tap shows the screen-map overlay.
/// 3. Releasing the modifier commits: the frontmost window on the final screen
///    gets focus. `cancel` instead puts the cursor back where it started.
@MainActor
final class Blinker {
    var config: BlinkConfig
    /// Called with `true` when a session starts and `false` when it ends, so the
    /// owner can register / unregister the session-only keys.
    var onSessionActiveChanged: ((Bool) -> Void)?

    private let highlighter = Highlighter()
    private let hud = SwitcherHUD()
    private var history = ScreenHistory()
    /// Last cursor position per display, for `Landing.remember`.
    private var remembered: [CGDirectDisplayID: CGPoint] = [:]

    private var session: SwitchSession?
    private var releaseTimer: Timer?
    private var hudTimer: Timer?

    /// How long the modifier must stay down before the overlay appears, so a
    /// quick tap stays a pure blink (⌘Tab behaves the same way).
    private static let hudDelay: TimeInterval = 0.18

    init(config: BlinkConfig) {
        self.config = config
    }

    func perform(_ action: Action) {
        log.debug("perform \(action.configName, privacy: .public) (switching: \(self.session != nil))")
        let displays = SystemDisplays.current()
        let cursor = Cursor.location
        guard let current = ScreenNavigator.display(containing: cursor, in: displays) else { return }

        if session == nil {
            if action == .cancel { return }
            begin(displays: displays, current: current, cursor: cursor)
        }
        guard var session else { return }

        let target: Display?
        switch action {
        case .nextScreen:
            target = session.step(1)
        case .previousScreen:
            target = session.step(-1)
        case .screen(let direction):
            target = ScreenNavigator.neighbor(of: session.target, direction: direction, in: displays, wrap: config.wrapAround)
        case .screenNumber(let n):
            target = ScreenNavigator.display(number: n, in: displays)
        case .cancel:
            end(commit: false)
            return
        }
        if let target { session.select(target) }
        self.session = session

        if let target, target.id != current.id {
            remembered[current.id] = cursor
            moveCursor(to: target)
        } else if config.highlight {
            // Nowhere to go — still show where the cursor is, which doubles as a
            // "find my mouse" gesture on single-display setups.
            highlighter.flash(at: cursor)
        }
        if hud.isVisible { hud.show(displays: displays, target: session.target) }
    }

    /// Drops remembered positions for displays that are gone.
    func displaysChanged() {
        let ids = Set(SystemDisplays.current().map(\.id))
        remembered = remembered.filter { ids.contains($0.key) }
        if session != nil { end(commit: false) }
    }

    // MARK: - Session

    private func begin(displays: [Display], current: Display, cursor: CGPoint) {
        // The cursor may have been moved to another screen by hand since the last
        // switch; that screen is now the most recent one.
        history.visit(current.id)
        session = SwitchSession(origin: cursor, order: history.order(of: displays, current: current))
        log.debug("session begin")
        onSessionActiveChanged?(true)

        // Carbon hotkeys report key presses only, not the modifier release, and
        // watching modifier keys globally would need extra permissions. Polling
        // the modifier state while a session is open is cheap and needs none.
        let required = config.resolvedModifiers().modifiers.cgEventFlags
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let held = CGEventSource.flagsState(.combinedSessionState)
                if !held.contains(required) { self?.end(commit: true) }
            }
        }
        RunLoop.main.add(releaseTimer!, forMode: .common)

        if config.showSwitcher && displays.count > 1 {
            hudTimer = Timer.scheduledTimer(withTimeInterval: Self.hudDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let session = self.session else { return }
                    self.hud.show(displays: SystemDisplays.current(), target: session.target)
                }
            }
            RunLoop.main.add(hudTimer!, forMode: .common)
        }
    }

    private func end(commit: Bool) {
        releaseTimer?.invalidate()
        releaseTimer = nil
        hudTimer?.invalidate()
        hudTimer = nil
        hud.hide()
        guard let session else { return }
        self.session = nil
        log.debug("session end (commit: \(commit))")
        onSessionActiveChanged?(false)

        if commit {
            let target = session.target
            guard target.id != session.originDisplay.id else { return }
            history.visit(target.id)
            if config.focusWindow, let window = Windows.frontmost(on: target) { Windows.focus(window) }
        } else {
            let cursor = Cursor.location
            if let current = ScreenNavigator.display(containing: cursor, in: SystemDisplays.current()) {
                remembered[current.id] = cursor
            }
            Cursor.move(to: session.origin)
            if config.highlight { highlighter.flash(at: session.origin) }
        }
    }

    private func moveCursor(to display: Display) {
        let point: CGPoint
        switch config.landing {
        case .remember:
            point = ScreenNavigator.landingPoint(on: display, preferred: remembered[display.id])
        case .center:
            point = display.center
        case .window:
            if let window = Windows.frontmost(on: display) {
                let visible = window.frame.intersection(display.frame)
                point = ScreenNavigator.clamp(CGPoint(x: visible.midX, y: visible.midY), to: display.frame)
            } else {
                point = display.center
            }
        }
        Cursor.move(to: point)
        if config.highlight { highlighter.flash(at: point) }
    }
}
