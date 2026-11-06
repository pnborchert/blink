import Foundation
import Testing
@testable import BlinkCore

@Suite struct ConfigTests {
    private func binding(_ action: Action, in config: BlinkConfig) -> Binding? {
        config.resolvedBindings().bindings.first { $0.action == action }
    }

    @Test func emptyFileGivesDefaults() throws {
        let config = try BlinkConfig.decode(from: Data("{}".utf8))
        #expect(config == .default)
        #expect(config.resolvedBindings().issues.isEmpty)
    }

    @Test func defaultsAreOptionTabWithSessionOnlyArrows() {
        let config = BlinkConfig.default
        #expect(binding(.nextScreen, in: config)?.shortcut.description == "⌥⇥")
        #expect(binding(.previousScreen, in: config)?.shortcut.description == "⌥⇧⇥")
        #expect(binding(.nextScreen, in: config)?.isGlobal == true)
        #expect(binding(.previousScreen, in: config)?.isGlobal == true)
        #expect(config.showSwitcher == false)
        // ⌥← and ⌥1 must stay usable in other apps: only active while switching.
        #expect(binding(.screen(.left), in: config)?.shortcut.description == "⌥←")
        #expect(binding(.screen(.left), in: config)?.isGlobal == false)
        #expect(binding(.screenNumber(1), in: config)?.isGlobal == false)
        #expect(binding(.cancel, in: config)?.isGlobal == false)
    }

    @Test func changingModifiersAppliesToEveryKey() {
        var config = BlinkConfig.default
        config.modifiers = "ctrl+alt+cmd"
        #expect(binding(.nextScreen, in: config)?.shortcut.description == "⌃⌥⌘⇥")
        #expect(binding(.screen(.up), in: config)?.shortcut.description == "⌃⌥⌘↑")
        #expect(binding(.previousScreen, in: config)?.shortcut.description == "⌃⌥⇧⌘⇥")
    }

    @Test func recordedShortcutSetsForwardBackwardAndModifiers() throws {
        var config = BlinkConfig.default
        config.setSwitchShortcut(try Shortcut(parsing: "cmd+§"))
        #expect(config.modifiers == "cmd")
        #expect(config.forwardShortcut?.description == "⌘§")
        #expect(binding(.previousScreen, in: config)?.shortcut.description == "⇧⌘§")
        // The modifiers held while switching follow the recorded shortcut.
        #expect(binding(.screen(.right), in: config)?.shortcut.description == "⌘→")
        #expect(config.resolvedBindings().issues.isEmpty)

        config.setSwitchShortcut(try Shortcut(parsing: "ctrl+alt+cmd+f5"))
        #expect(config.forwardShortcut?.description == "⌃⌥⌘F5")
        #expect(binding(.previousScreen, in: config)?.shortcut.description == "⌃⌥⇧⌘F5")
    }

    @Test func specialKeyNamesFromKeyCodes() {
        #expect(Shortcut.specialKeyName(forKeyCode: 0x30) == "tab")
        #expect(Shortcut.specialKeyName(forKeyCode: 0x7B) == "left")
        #expect(Shortcut.specialKeyName(forKeyCode: 0x60) == "f5")
        #expect(Shortcut.specialKeyName(forKeyCode: 0x00) == nil) // "a" is a character key
    }

    @Test func directKeysMakesArrowsGlobalButNotCancel() {
        var config = BlinkConfig.default
        config.directKeys = true
        #expect(binding(.screen(.right), in: config)?.isGlobal == true)
        #expect(binding(.screenNumber(3), in: config)?.isGlobal == true)
        #expect(binding(.cancel, in: config)?.isGlobal == false)
    }

    @Test func invalidModifiersFallBackToDefault() {
        var config = BlinkConfig.default
        config.modifiers = "shift"
        let resolved = config.resolvedBindings()
        #expect(resolved.issues.map(\.name) == ["modifiers"])
        #expect(binding(.nextScreen, in: config)?.shortcut.description == "⌥⇥")
        config.modifiers = "hyper"
        #expect(config.resolvedModifiers().issue != nil)
    }

    @Test func partialFileKeepsOtherDefaults() throws {
        let json = #"{"landing": "center", "keys": {"next": "§"}}"#
        let config = try BlinkConfig.decode(from: Data(json.utf8))
        #expect(config.landing == .center)
        #expect(config.focusWindow == BlinkConfig.default.focusWindow)
        #expect(binding(.nextScreen, in: config)?.shortcut.description == "⌥§")
        #expect(binding(.screen(.right), in: config) != nil)
    }

    @Test func roundTrips() throws {
        var config = BlinkConfig.default
        config.highlight = false
        config.landing = .window
        config.modifiers = "ctrl+cmd"
        config.keys["screen2"] = ""
        #expect(try BlinkConfig.decode(from: config.encoded()) == config)
    }

    @Test func emptyStringUnbinds() throws {
        let json = #"{"keys": {"previous": ""}}"#
        let resolved = try BlinkConfig.decode(from: Data(json.utf8)).resolvedBindings()
        #expect(!resolved.bindings.contains { $0.action == .previousScreen })
        #expect(resolved.issues.isEmpty)
    }

    @Test func reportsInvalidAndDuplicateKeys() throws {
        let json = #"{"keys": {"jump": "j", "up": "nope", "screen1": "left"}}"#
        let resolved = try BlinkConfig.decode(from: Data(json.utf8)).resolvedBindings()
        let names = Set(resolved.issues.map(\.name))
        #expect(names.contains("jump"))
        #expect(names.contains("up"))
        // "left" and "screen1" share ⌥←; exactly one of them is rejected.
        #expect(names.contains("left") != names.contains("screen1"))
        #expect(resolved.bindings.first?.action == .nextScreen)
    }

    @Test func actionNamesRoundTrip() {
        for action in Action.all {
            #expect(Action(configName: action.configName) == action)
        }
        #expect(Action(configName: "screen10") == nil)
    }

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) { try BlinkConfig.decode(from: Data(#"{"landing": "nowhere"}"#.utf8)) }
    }
}
