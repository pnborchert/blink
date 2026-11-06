# Configuration

Blink keeps its settings in `~/.config/blink/config.json` (or `$XDG_CONFIG_HOME/blink/config.json`). The file is created on first launch, the menu writes to it, and Blink picks up your edits as soon as you save. Every key is optional — anything missing falls back to the default.

```json
{
  "modifiers": "alt",
  "keys": {
    "next": "tab",
    "previous": "shift+tab",
    "left": "left",
    "right": "right",
    "up": "up",
    "down": "down",
    "screen1": "1",
    "screen2": "2",
    "cancel": "escape"
  },
  "directKeys": false,
  "landing": "remember",
  "focusWindow": true,
  "highlight": true,
  "showSwitcher": false,
  "wrapAround": true
}
```

| Option | What it does | Default |
| --- | --- | --- |
| `modifiers` | The keys you hold. Any mix of `ctrl`, `alt`, `cmd` (plus `shift` if you really want). | `alt` |
| `keys` | Which key does what, on top of `modifiers`. Set one to `""` to turn it off. Actions: `next`, `previous`, `left`, `right`, `up`, `down`, `screen1`…`screen9`, `cancel`. | see above |
| `directKeys` | Make the arrows and numbers work without pressing `next` first. They then no longer reach other apps. | `false` |
| `landing` | Where the cursor lands: `remember` (last spot on that screen), `center`, or `window` (center of the front window). | `remember` |
| `focusWindow` | Focus the front window on the new screen when you let go. Needs Accessibility access. | `true` |
| `highlight` | Flash a small ring where the cursor landed. | `true` |
| `showSwitcher` | Show a map of your screens while you hold the modifier. | `false` |
| `wrapAround` | Pressing → on the rightmost screen jumps to the leftmost one (and so on). | `true` |

**Key names:** `a`–`z`, `0`–`9`, punctuation like `§` `` ` `` `,` `[` (the minus key is `minus`), `left` `right` `up` `down`, `tab` `space` `return` `escape` `delete`, `home` `end` `pageup` `pagedown`, `f1`–`f20`. Character keys follow your keyboard layout, so `z` is the key labelled Z even on QWERTZ.

If a shortcut is invalid or taken by another app, Blink tells you which one and keeps the rest working.

## Scripting

```sh
/Applications/Blink.app/Contents/MacOS/Blink --perform next
```

Any action name works (`next`, `previous`, `left`, `screen2`, …). If Blink is running, it does the move (so it remembers where you were); otherwise the command does it by itself. Handy for Raycast, Alfred, BetterTouchTool, Karabiner or skhd.

## Troubleshooting

- **Shortcut does nothing:** another app probably owns it — record a different one.
- **Window doesn't get focus:** check *System Settings → Privacy & Security → Accessibility*. If you build Blink yourself, macOS forgets that permission after every rebuild (the app is signed ad hoc). Remove Blink from the list and add it again, or build with your own signing certificate: `SIGN_IDENTITY="My Cert" make install`.
- **Building in an iCloud-synced folder** (like `~/Documents`) fails with *"resource fork, Finder information, or similar detritus not allowed"*. The Makefile works around it by building in `~/Library/Caches/blink-build`; set `BUILD_DIR=…` to choose another place.
- **Debug log:** `/usr/bin/log stream --level debug --predicate 'subsystem == "io.github.pnborchert.blink"'`
