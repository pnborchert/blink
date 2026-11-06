import Foundation
import Testing
@testable import BlinkCore

@Suite struct ShortcutTests {
    @Test func parsesTextForm() throws {
        let s = try Shortcut(parsing: "ctrl+alt+cmd+right")
        #expect(s.key == "right")
        #expect(s.keyCode == 0x7C)
        #expect(s.modifiers == [.control, .option, .command])
        #expect(s.carbonModifiers == (1 << 12 | 1 << 11 | 1 << 8))
        #expect(s.description == "⌃⌥⌘→")
        #expect(s.configString == "ctrl+alt+cmd+right")
    }

    @Test func parsesAliasesSymbolsAndCase() throws {
        #expect(try Shortcut(parsing: "Control-Option-Command-Left") == Shortcut(parsing: "ctrl+alt+cmd+left"))
        #expect(try Shortcut(parsing: "⌃⌥⌘←") == Shortcut(parsing: "ctrl+opt+cmd+left"))
        #expect(try Shortcut(parsing: "cmd + shift + Space").description == "⇧⌘Space")
        #expect(try Shortcut(parsing: "ctrl+alt+minus").keyCode == 0x1B)
        #expect(try Shortcut(parsing: "hyper f5".replacingOccurrences(of: "hyper", with: "ctrl alt shift cmd")).description == "⌃⌥⇧⌘F5")
    }

    @Test func sectionKeyAndModifierSets() throws {
        let s = try Shortcut(parsing: "cmd+§")
        #expect(s.keyCode == 0x0A)
        #expect(s.isCharacterKey)
        #expect(s.description == "⌘§")
        #expect(try Shortcut(parsing: "⌘section") == s)
        #expect(try Shortcut(parsing: "right").adding([.command, .control]).description == "⌃⌘→")
        #expect(try Shortcut.Modifiers(parsing: "ctrl+alt+cmd") == [.control, .option, .command])
        #expect(try Shortcut.Modifiers(parsing: "⌃⌥⌘").configString == "ctrl+alt+cmd")
        #expect(throws: Shortcut.ParseError.unknownToken("k")) { try Shortcut.Modifiers(parsing: "cmd+k") }
    }

    @Test func rejectsBadInput() {
        #expect(throws: Shortcut.ParseError.empty) { try Shortcut(parsing: "  ") }
        #expect(throws: Shortcut.ParseError.missingKey) { try Shortcut(parsing: "ctrl+cmd") }
        #expect(throws: Shortcut.ParseError.unknownToken("hyper")) { try Shortcut(parsing: "hyper+k") }
        #expect(throws: Shortcut.ParseError.multipleKeys("a", "b")) { try Shortcut(parsing: "cmd+a+b") }
    }
}
