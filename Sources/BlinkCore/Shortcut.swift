/// A global keyboard shortcut such as `ctrl+alt+cmd+right`.
///
/// Key codes are macOS virtual key codes (`kVK_*` from Carbon). For character
/// keys (letters, digits, punctuation, `§`) `keyCode` is the US-ANSI position;
/// the app re-resolves those through the active keyboard layout, so `z` means
/// the key labelled Z on QWERTZ too.
public struct Shortcut: Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Parses a modifier-only string such as `ctrl+alt+cmd` or `⌃⌥⌘`.
        public init(parsing string: String) throws {
            let tokens = Shortcut.tokenize(string)
            guard !tokens.isEmpty else { throw ParseError.empty }
            var result: Modifiers = []
            for token in tokens {
                guard let mod = Shortcut.modifierNames[token] else { throw ParseError.unknownToken(token) }
                result.insert(mod)
            }
            self = result
        }

        /// `⌃⌥⇧⌘` order, as macOS menus show them.
        public var symbols: String {
            var s = ""
            if contains(.control) { s += "⌃" }
            if contains(.option) { s += "⌥" }
            if contains(.shift) { s += "⇧" }
            if contains(.command) { s += "⌘" }
            return s
        }

        /// Config-file spelling, e.g. `ctrl+alt+cmd`.
        public var configString: String {
            var parts: [String] = []
            if contains(.control) { parts.append("ctrl") }
            if contains(.option) { parts.append("alt") }
            if contains(.shift) { parts.append("shift") }
            if contains(.command) { parts.append("cmd") }
            return parts.joined(separator: "+")
        }
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case unknownToken(String)
        case missingKey
        case multipleKeys(String, String)

        public var description: String {
            switch self {
            case .empty: return "shortcut is empty"
            case .unknownToken(let t): return "unknown key or modifier '\(t)'"
            case .missingKey: return "shortcut has modifiers but no key"
            case .multipleKeys(let a, let b): return "shortcut has more than one key ('\(a)' and '\(b)')"
            }
        }
    }

    /// Canonical key name, e.g. `right`, `a`, `f5`.
    public let key: String
    public let keyCode: UInt32
    public let modifiers: Modifiers

    public init(key: String, modifiers: Modifiers) throws {
        let name = Self.canonicalKey(key.lowercased())
        guard let code = Self.keyCodes[name] else { throw ParseError.unknownToken(key) }
        self.key = name
        self.keyCode = code
        self.modifiers = modifiers
    }

    /// Parses strings like `ctrl+alt+cmd+right`, `cmd+shift+space` or `⌃⌥⌘←`.
    /// Tokens are case-insensitive and may be separated by `+`, `-` or spaces
    /// (so the minus key itself is spelled `minus`).
    public init(parsing string: String) throws {
        let tokens = Self.tokenize(string)
        guard !tokens.isEmpty else { throw ParseError.empty }

        var modifiers: Modifiers = []
        var key: String?
        for token in tokens {
            if let mod = Self.modifierNames[token] {
                modifiers.insert(mod)
                continue
            }
            let name = Self.canonicalKey(token)
            guard Self.keyCodes[name] != nil else { throw ParseError.unknownToken(token) }
            if let existing = key { throw ParseError.multipleKeys(existing, name) }
            key = name
        }
        guard let key else { throw ParseError.missingKey }
        try self.init(key: key, modifiers: modifiers)
    }

    /// The same key with additional modifiers held.
    public func adding(_ extra: Modifiers) -> Shortcut {
        // Can't fail: `key` is already a valid canonical name.
        try! Shortcut(key: key, modifiers: modifiers.union(extra))
    }

    /// The name of a non-character key (`tab`, `left`, `f5`, …) from its key code.
    /// Character keys are layout dependent and resolved by the app instead.
    public static func specialKeyName(forKeyCode code: UInt32) -> String? {
        keyCodes.first { $0.value == code && $0.key.count > 1 }?.key
    }

    /// Keys that type a character (as opposed to arrows, F-keys, …) and whose
    /// position therefore depends on the keyboard layout.
    public var isCharacterKey: Bool { key.count == 1 }

    /// Modifier flags in the format expected by Carbon's `RegisterEventHotKey`.
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 1 << 8 }   // cmdKey
        if modifiers.contains(.shift) { flags |= 1 << 9 }     // shiftKey
        if modifiers.contains(.option) { flags |= 1 << 11 }   // optionKey
        if modifiers.contains(.control) { flags |= 1 << 12 }  // controlKey
        return flags
    }

    /// Human readable form using the standard macOS symbols, e.g. `⌃⌥⌘→`.
    public var description: String {
        modifiers.symbols + keySymbol
    }

    /// Just the key, e.g. `⇥` or `A`.
    public var keySymbol: String {
        Self.keySymbols[key] ?? key.uppercased()
    }

    /// The config-file spelling, e.g. `ctrl+alt+cmd+right`.
    public var configString: String {
        modifiers.isEmpty ? key : modifiers.configString + "+" + key
    }

    // MARK: - Tables

    fileprivate static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current.lowercased()) }
            current = ""
        }
        for ch in string {
            if ch == "+" || ch == " " || ch == "-" {
                flush()
            } else if symbolTokens.contains(ch) {
                // Symbols like ⌘ or ← stand on their own even without separators.
                flush()
                tokens.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        flush()
        return tokens
    }

    private static let symbolTokens: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "←", "→", "↑", "↓"]

    fileprivate static let modifierNames: [String: Modifiers] = [
        "ctrl": .control, "control": .control, "⌃": .control,
        "alt": .option, "opt": .option, "option": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
    ]

    private static let keyAliases: [String: String] = [
        "←": "left", "→": "right", "↑": "up", "↓": "down",
        "arrowleft": "left", "arrowright": "right", "arrowup": "up", "arrowdown": "down",
        "enter": "return", "esc": "escape", "backspace": "delete",
        "pgup": "pageup", "pgdown": "pagedown",
        "minus": "-", "equal": "=", "equals": "=", "comma": ",", "period": ".", "slash": "/",
        "backslash": "\\", "semicolon": ";", "quote": "'", "grave": "`", "backtick": "`",
        "leftbracket": "[", "rightbracket": "]", "section": "§",
    ]

    private static func canonicalKey(_ name: String) -> String { keyAliases[name] ?? name }

    static let keyCodes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32, "§": 0x0A,
        "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "escape": 0x35,
        "forwarddelete": 0x75, "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
        "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71, "f16": 0x6A, "f17": 0x40, "f18": 0x4F,
        "f19": 0x50, "f20": 0x5A,
    ]

    private static let keySymbols: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "return": "↩", "tab": "⇥", "space": "Space", "delete": "⌫", "escape": "⎋",
        "forwarddelete": "⌦", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]
}
