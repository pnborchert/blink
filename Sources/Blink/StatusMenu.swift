import AppKit
import BlinkCore
import ServiceManagement

/// The menu bar icon and its menu. Rebuilt every time it opens, so it always
/// reflects the current screens, settings and permissions.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private var config: BlinkConfig { controller.config }

    init(controller: AppController) {
        self.controller = controller
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Blink")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addBlinkItems(to: menu)
        menu.addItem(.separator())
        addScreenItems(to: menu)
        menu.addItem(.separator())
        addSettingsItems(to: menu)
        menu.addItem(.separator())
        addAppItems(to: menu)
    }

    // MARK: - Sections

    private func addBlinkItems(to menu: NSMenu) {
        for binding in controller.activeBindings where binding.action.isTrigger {
            menu.addItem(actionItem(binding.action, title: binding.action.description, shortcut: binding.shortcut))
        }
        let modifiers = config.resolvedModifiers().modifiers.symbols
        let hint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hint.attributedTitle = NSAttributedString(
            string: "Keep holding \(modifiers) for ← → ↑ ↓, 1–9, esc to cancel",
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        hint.isEnabled = false
        menu.addItem(hint)
    }

    private func addScreenItems(to menu: NSMenu) {
        if #available(macOS 14, *) {
            menu.addItem(.sectionHeader(title: "Screens"))
        } else {
            let header = NSMenuItem(title: "Screens", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        let displays = ScreenNavigator.ordered(SystemDisplays.current())
        let current = ScreenNavigator.display(containing: Cursor.location, in: displays)
        for (index, display) in displays.enumerated() {
            let action = Action.screenNumber(index + 1)
            let size = "\(Int(display.frame.width))×\(Int(display.frame.height))"
            // Numbers only show a shortcut when they work without the trigger (`directKeys`).
            let shortcut = controller.activeBindings.first { $0.action == action }?.shortcut
            let item = actionItem(action, title: "\(index + 1)  \(SystemDisplays.name(of: display.id))  (\(size))", shortcut: shortcut)
            item.state = display.id == current?.id ? .on : .off
            menu.addItem(item)
        }
    }

    private func addSettingsItems(to menu: NSMenu) {
        menu.addItem(shortcutSubmenu())
        menu.addItem(landingSubmenu())
        menu.addItem(toggle("Focus Window on Target Screen", \.focusWindow))
        menu.addItem(toggle("Highlight Cursor After Blink", \.highlight))
        menu.addItem(toggle("Show Screen Switcher While Holding", \.showSwitcher))
        menu.addItem(toggle("Wrap Around at Last Screen", \.wrapAround))
    }

    private func addAppItems(to menu: NSMenu) {
        if !Accessibility.isTrusted {
            let item = item("Grant Accessibility Access…", #selector(openAccessibilitySettings))
            item.toolTip = "Needed to focus the window on the target screen. Moving the cursor works without it."
            menu.addItem(item)
        }
        menu.addItem(item("Open Config File", #selector(openConfig)))
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let about = NSMenuItem(title: "Blink \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Blink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func shortcutSubmenu() -> NSMenuItem {
        let forward = config.forwardShortcut
        let submenu = NSMenu()
        submenu.addItem(item("Record New Shortcut…", #selector(recordShortcut)))
        let defaultShortcut = BlinkConfig.default.forwardShortcut
        let reset = item("Reset to \(defaultShortcut?.description ?? "Default")", #selector(resetShortcut))
        reset.isEnabled = forward != defaultShortcut
        submenu.addItem(reset)

        submenu.addItem(.separator())
        let modifiers = config.resolvedModifiers().modifiers.symbols
        let key = forward?.keySymbol ?? "the Shortcut"
        let direct = toggle("Use Arrows and 1–9 Without \(key) First", \.directKeys)
        direct.toolTip = "Makes \(modifiers)← etc. work directly. They then no longer reach other apps."
        submenu.addItem(direct)

        let item = NSMenuItem(title: "Shortcut: \(forward?.description ?? "none")", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func landingSubmenu() -> NSMenuItem {
        let submenu = NSMenu()
        let choices: [(Landing, String)] = [
            (.remember, "Last Position on That Screen"),
            (.center, "Center of Screen"),
            (.window, "Center of Frontmost Window"),
        ]
        for (landing, title) in choices {
            let entry = item(title, #selector(setLanding(_:)))
            entry.representedObject = landing.rawValue
            entry.state = config.landing == landing ? .on : .off
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: "Cursor Lands At", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: - Item helpers

    private func item(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func actionItem(_ action: Action, title: String, shortcut: Shortcut?) -> NSMenuItem {
        let item = item(title, #selector(performAction(_:)))
        item.representedObject = action.configName
        if let shortcut { item.setShortcut(shortcut) }
        return item
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<BlinkConfig, Bool>) -> NSMenuItem {
        let item = item(title, #selector(toggleSetting(_:)))
        item.representedObject = keyPath
        item.state = config[keyPath: keyPath] ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let action = Action(configName: name) else { return }
        // Let the menu close first so focus changes aren't undone by it.
        DispatchQueue.main.async { [controller] in
            MainActor.assumeIsolated { controller.blinker.perform(action) }
        }
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        guard let keyPath = sender.representedObject as? WritableKeyPath<BlinkConfig, Bool> else { return }
        controller.update { $0[keyPath: keyPath].toggle() }
    }

    @objc private func setLanding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let landing = Landing(rawValue: raw) else { return }
        controller.update { $0.landing = landing }
    }

    @objc private func recordShortcut() { controller.recordShortcut() }
    @objc private func resetShortcut() { controller.resetShortcut() }

    @objc private func openAccessibilitySettings() {
        Accessibility.requestIfNeeded()
        Accessibility.openSettings()
    }

    @objc private func openConfig() {
        let url = controller.store.url
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Alert.show("Could not change Launch at Login", error.localizedDescription)
        }
    }
}

private extension NSMenuItem {
    /// Shows a shortcut next to the item, using native menu rendering.
    func setShortcut(_ shortcut: Shortcut) {
        guard let key = Self.keyEquivalent(for: shortcut.key) else { return }
        keyEquivalent = key
        keyEquivalentModifierMask = shortcut.modifiers.eventFlags
    }

    static func keyEquivalent(for key: String) -> String? {
        func function(_ code: Int) -> String { String(UnicodeScalar(UInt16(code)).map(Character.init) ?? " ") }
        switch key {
        case "left": return function(NSLeftArrowFunctionKey)
        case "right": return function(NSRightArrowFunctionKey)
        case "up": return function(NSUpArrowFunctionKey)
        case "down": return function(NSDownArrowFunctionKey)
        case "home": return function(NSHomeFunctionKey)
        case "end": return function(NSEndFunctionKey)
        case "pageup": return function(NSPageUpFunctionKey)
        case "pagedown": return function(NSPageDownFunctionKey)
        case "forwarddelete": return function(NSDeleteFunctionKey)
        case "space": return " "
        case "return": return "\r"
        case "tab": return "\t"
        case "escape": return "\u{1b}"
        case "delete": return "\u{8}"
        default:
            if key.hasPrefix("f"), let n = Int(key.dropFirst()), (1...20).contains(n) {
                return function(NSF1FunctionKey + n - 1)
            }
            return key.count == 1 ? key : nil
        }
    }
}
