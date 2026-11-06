import Foundation

/// Something a key can trigger.
public enum Action: Hashable, Sendable, CustomStringConvertible {
    /// Step through screens in most-recently-used order (like ⌘Tab through apps).
    case nextScreen
    case previousScreen
    case screen(Direction)
    case screenNumber(Int)
    /// Abort the current switch and put the cursor back where it started.
    case cancel

    /// Every action that can be bound in the config file, in menu order.
    public static let all: [Action] =
        [.nextScreen, .previousScreen] + Direction.allCases.map(Action.screen) + (1...9).map(Action.screenNumber) + [.cancel]

    /// Triggers are always active. The other keys only work while the modifier
    /// is held after a trigger — like the arrow keys inside the ⌘Tab switcher —
    /// so they don't take e.g. ⌘← or ⌘1 away from other apps.
    public var isTrigger: Bool {
        switch self {
        case .nextScreen, .previousScreen: return true
        default: return false
        }
    }

    /// The key used in the config file's `keys` object.
    public var configName: String {
        switch self {
        case .nextScreen: return "next"
        case .previousScreen: return "previous"
        case .screen(let d): return d.rawValue
        case .screenNumber(let n): return "screen\(n)"
        case .cancel: return "cancel"
        }
    }

    public init?(configName: String) {
        guard let match = Action.all.first(where: { $0.configName == configName }) else { return nil }
        self = match
    }

    public var description: String {
        switch self {
        case .nextScreen: return "Blink Forward"
        case .previousScreen: return "Blink Backward"
        case .screen(let d): return "Blink \(d.rawValue.capitalized)"
        case .screenNumber(let n): return "Blink to Screen \(n)"
        case .cancel: return "Cancel"
        }
    }
}

/// Where the cursor lands on the target screen.
public enum Landing: String, Codable, CaseIterable, Sendable {
    /// Where the cursor last was on that screen (falls back to the center).
    case remember
    /// The center of the screen.
    case center
    /// The center of the frontmost window on that screen (falls back to the center).
    case window
}

/// One resolved key binding.
public struct Binding: Equatable, Sendable {
    public let action: Action
    /// Including the shared modifiers.
    public let shortcut: Shortcut
    /// Registered permanently (triggers, or every key with `directKeys`);
    /// otherwise only while a switch is in progress.
    public let isGlobal: Bool
}

/// User configuration, stored as JSON (default: `~/.config/blink/config.json`).
///
/// Every field is optional in the file; missing fields take their defaults, so a
/// config written by an older version keeps working.
public struct BlinkConfig: Equatable, Sendable {
    /// Held together with every key below, e.g. `alt` or `ctrl+alt+cmd`.
    public var modifiers: String
    /// Action config name → key, optionally with extra modifiers (`shift+tab`).
    /// Merged over `defaultKeys`; an empty string disables the action.
    public var keys: [String: String]
    /// Make arrows/numbers work without pressing the trigger first. Off by
    /// default because e.g. ⌘← would stop working in text fields.
    public var directKeys: Bool
    public var landing: Landing
    /// Also give keyboard focus to the frontmost window on the target screen.
    public var focusWindow: Bool
    /// Briefly draw a ring around the cursor after it moves.
    public var highlight: Bool
    /// Show the ⌘Tab-style screen map while the modifier is held.
    public var showSwitcher: Bool
    /// Arrow past the last screen in a direction continues at the other end.
    public var wrapAround: Bool

    public static let defaultModifiers = "alt"

    public static let defaultKeys: [String: String] = {
        var keys = [
            "next": "tab",
            "previous": "shift+tab",
            "left": "left",
            "right": "right",
            "up": "up",
            "down": "down",
            "cancel": "escape",
        ]
        for n in 1...9 { keys["screen\(n)"] = "\(n)" }
        return keys
    }()

    public static let `default` = BlinkConfig(
        modifiers: defaultModifiers,
        keys: defaultKeys,
        directKeys: false,
        landing: .remember,
        focusWindow: true,
        highlight: true,
        showSwitcher: false,
        wrapAround: true
    )

    public init(
        modifiers: String, keys: [String: String], directKeys: Bool, landing: Landing,
        focusWindow: Bool, highlight: Bool, showSwitcher: Bool, wrapAround: Bool
    ) {
        self.modifiers = modifiers
        self.keys = keys
        self.directKeys = directKeys
        self.landing = landing
        self.focusWindow = focusWindow
        self.highlight = highlight
        self.showSwitcher = showSwitcher
        self.wrapAround = wrapAround
    }

    /// A problem with one entry. The rest of the config still applies.
    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        public let name: String
        public let message: String
        public var description: String { "\(name): \(message)" }
    }

    /// The shared modifiers; falls back to the default if invalid or empty.
    public func resolvedModifiers() -> (modifiers: Shortcut.Modifiers, issue: Issue?) {
        let fallback = try! Shortcut.Modifiers(parsing: Self.defaultModifiers)
        do {
            let mods = try Shortcut.Modifiers(parsing: modifiers)
            if mods.subtracting(.shift).isEmpty {
                return (fallback, Issue(name: "modifiers", message: "needs at least one of ctrl, alt, cmd"))
            }
            return (mods, nil)
        } catch let error as Shortcut.ParseError {
            return (fallback, Issue(name: "modifiers", message: error.description))
        } catch {
            return (fallback, Issue(name: "modifiers", message: "\(error)"))
        }
    }

    /// The forward shortcut, e.g. `⌥⇥` (nil if unbound or invalid).
    public var forwardShortcut: Shortcut? {
        resolvedBindings().bindings.first { $0.action == .nextScreen }?.shortcut
    }

    /// Makes `shortcut` the forward blink and the same plus ⇧ the backward one
    /// (like ⌘Tab / ⌘⇧Tab). Its modifiers become the ones held while switching.
    public mutating func setSwitchShortcut(_ shortcut: Shortcut) {
        modifiers = shortcut.modifiers.subtracting(.shift).configString
        keys["next"] = shortcut.key
        keys["previous"] = "shift+" + shortcut.key
    }

    /// Resolves the key table into bindings (in menu order), reporting invalid entries.
    public func resolvedBindings() -> (bindings: [Binding], issues: [Issue]) {
        let (base, modifierIssue) = resolvedModifiers()
        var issues = modifierIssue.map { [$0] } ?? []
        let merged = Self.defaultKeys.merging(keys) { _, user in user }
        var bindings: [Binding] = []
        var seen: [Shortcut: Action] = [:]

        for name in merged.keys.sorted() {
            let value = merged[name]!.trimmingCharacters(in: .whitespaces)
            guard let action = Action(configName: name) else {
                issues.append(Issue(name: name, message: "unknown action"))
                continue
            }
            if value.isEmpty { continue }
            do {
                let shortcut = try Shortcut(parsing: value).adding(base)
                if let other = seen[shortcut] {
                    issues.append(Issue(name: name, message: "\(shortcut) is already used by '\(other.configName)'"))
                    continue
                }
                seen[shortcut] = action
                let global = action.isTrigger || (directKeys && action != .cancel)
                bindings.append(Binding(action: action, shortcut: shortcut, isGlobal: global))
            } catch let error as Shortcut.ParseError {
                issues.append(Issue(name: name, message: error.description))
            } catch {
                issues.append(Issue(name: name, message: "\(error)"))
            }
        }
        bindings.sort { Action.all.firstIndex(of: $0.action)! < Action.all.firstIndex(of: $1.action)! }
        return (bindings, issues)
    }
}

extension BlinkConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case modifiers, keys, directKeys, landing, focusWindow, highlight, showSwitcher, wrapAround
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BlinkConfig.default
        modifiers = try c.decodeIfPresent(String.self, forKey: .modifiers) ?? d.modifiers
        keys = try c.decodeIfPresent([String: String].self, forKey: .keys) ?? d.keys
        directKeys = try c.decodeIfPresent(Bool.self, forKey: .directKeys) ?? d.directKeys
        landing = try c.decodeIfPresent(Landing.self, forKey: .landing) ?? d.landing
        focusWindow = try c.decodeIfPresent(Bool.self, forKey: .focusWindow) ?? d.focusWindow
        highlight = try c.decodeIfPresent(Bool.self, forKey: .highlight) ?? d.highlight
        showSwitcher = try c.decodeIfPresent(Bool.self, forKey: .showSwitcher) ?? d.showSwitcher
        wrapAround = try c.decodeIfPresent(Bool.self, forKey: .wrapAround) ?? d.wrapAround
    }

    public static func decode(from data: Data) throws -> BlinkConfig {
        try JSONDecoder().decode(BlinkConfig.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
