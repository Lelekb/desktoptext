# DesktopText

Put a quote, poem or reminder **directly on your macOS desktop**: always visible behind your
windows, click-through, no widget frame. One Swift file, AppKit only, no network, no dependencies.

## Run

```bash
swift DesktopText.swift
```

Or compile once: `swiftc -O DesktopText.swift -o DesktopText && ./DesktopText`

- **Move:** hold ⌥ Option and drag the text
- **Edit:** ⌥ Option + right-click the text: text, font, size, colour, opacity, alignment, spacing, shadow
- **Saved texts:** store several texts with their layout and switch between them
- **Multiple displays:** position is remembered per display
- **Quit:** Ctrl-C, or "Quit" in the editor

Settings live in `DesktopText.settings.json` next to the source file (plain JSON).

## Start at login (optional)
Compile the binary, edit the paths in `local.desktoptext.plist`, then:

```bash
cp local.desktoptext.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/local.desktoptext.plist
```

Feedback and ideas welcome in Issues. MIT License.
