import AppKit
import BlinkCore

/// Owns the config and wires it to the hotkeys and the `Blinker`. The menu and
/// the shortcut recorder change settings only through this class.
@MainActor
final class AppController {
    let store = ConfigStore()
    private(set) var config: BlinkConfig
    /// Successfully registered always-on bindings (shown in the menu).
    private(set) var activeBindings: [Binding] = []

    let blinker: Blinker
    /// Always-on shortcuts: forward / backward, plus everything with `directKeys`.
    private let globalHotkeys = HotkeyCenter()
    /// Arrows, numbers, esc: only registered while a switch is in progress, so
    /// e.g. ⌥← keeps working in text fields the rest of the time.
    private let sessionHotkeys = HotkeyCenter()
    private let recorder = ShortcutRecorder()
    private var configWatcher: DispatchSourceFileSystemObject?

    init() {
        let (config, error) = store.load()
        self.config = config
        blinker = Blinker(config: config)
        if let error { Alert.show("Blink config error", error) }
    }

    func start() {
        blinker.onSessionActiveChanged = { [weak self] active in self?.setSessionKeys(active: active) }
        reportProblems(registerHotkeys())
        if config.focusWindow { Accessibility.requestIfNeeded() }

        configWatcher = store.watch { [weak self] in self?.reloadConfig() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.blinker.displaysChanged() }
        }
        // Character keys map to different physical keys per keyboard layout.
        DistributedNotificationCenter.default().addObserver(
            forName: KeyboardLayout.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                KeyboardLayout.invalidate()
                _ = self?.registerHotkeys()
            }
        }
        // Sent by `Blink --perform <action>`.
        DistributedNotificationCenter.default().addObserver(
            forName: performNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let name = note.object as? String, let action = Action(configName: name) else { return }
            MainActor.assumeIsolated { self?.blinker.perform(action) }
        }
    }

    // MARK: - Settings

    /// Applies a change, saves it to the config file and re-registers hotkeys if needed.
    func update(_ change: (inout BlinkConfig) -> Void) {
        var updated = config
        change(&updated)
        apply(updated, save: true)
    }

    func reloadConfig() {
        let (loaded, error) = store.load()
        if let error {
            Alert.show("Blink config error", error + "\n\nKeeping the previous settings.")
            return
        }
        apply(loaded, save: false)
    }

    func recordShortcut() {
        // Free the current shortcut so pressing it again can be recorded.
        globalHotkeys.unregisterAll()
        recorder.record(current: config.forwardShortcut) { [weak self] shortcut in
            guard let self else { return }
            let before = self.config
            if let shortcut { self.update { $0.setSwitchShortcut(shortcut) } } // re-registers if changed
            if self.config == before {
                // Cancelled or the same shortcut again: restore the hotkeys freed above.
                self.reportProblems(self.registerHotkeys())
            }
        }
    }

    func resetShortcut() {
        update {
            $0.modifiers = BlinkConfig.default.modifiers
            $0.keys["next"] = BlinkConfig.defaultKeys["next"]
            $0.keys["previous"] = BlinkConfig.defaultKeys["previous"]
        }
    }

    private func apply(_ newConfig: BlinkConfig, save: Bool) {
        guard newConfig != config else { return }
        let old = config
        config = newConfig
        blinker.config = newConfig
        if save, let error = store.save(newConfig) { Alert.show("Could not save settings", error) }
        if newConfig.keys != old.keys || newConfig.modifiers != old.modifiers || newConfig.directKeys != old.directKeys {
            reportProblems(registerHotkeys())
        }
        if newConfig.focusWindow && !old.focusWindow { Accessibility.requestIfNeeded() }
    }

    // MARK: - Hotkeys

    /// Registers the always-on hotkeys; returns human-readable problems.
    private func registerHotkeys() -> [String] {
        globalHotkeys.unregisterAll()
        activeBindings.removeAll()
        let (bindings, issues) = config.resolvedBindings()
        var problems = issues.map(\.description)
        for binding in bindings where binding.isGlobal {
            let action = binding.action
            if globalHotkeys.register(binding.shortcut, handler: { [weak self] in self?.blinker.perform(action) }) {
                activeBindings.append(binding)
            } else {
                problems.append("\(action.configName): \(binding.shortcut) is already taken by another app or the system")
            }
        }
        return problems
    }

    private func setSessionKeys(active: Bool) {
        sessionHotkeys.unregisterAll()
        guard active else { return }
        for binding in config.resolvedBindings().bindings where !binding.isGlobal {
            let action = binding.action
            sessionHotkeys.register(binding.shortcut) { [weak self] in self?.blinker.perform(action) }
        }
    }

    private func reportProblems(_ problems: [String]) {
        if !problems.isEmpty { Alert.show("Some Blink shortcuts are not active", problems.joined(separator: "\n")) }
    }
}
