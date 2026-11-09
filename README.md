# SnipClip

Windows 11–style screenshots for macOS. Press **⌃⇧S** (Control‑Shift‑S), drag over the part of the screen you want, and paste it anywhere with **⌘V**. No file is saved unless you turn that on.

While dragging: **Space** switches to window capture and **Esc** cancels.

## Download

[Download the latest version](https://github.com/Nikita-Shulga/SnipClip/releases/latest) (`SnipClip-1.0-mac-universal.zip`). One app for both Apple Silicon and Intel Macs, macOS 13 or later.

Unzip it and drag **SnipClip** to Applications. The app isn't signed by Apple yet, so the first time you open it macOS blocks it: go to *System Settings → Privacy & Security* and click *Open Anyway*. If macOS says the app is damaged, run `xattr -cr "/Applications/SnipClip.app"` once.

## Features

**Recent snips.** Your last 20 snips are kept for 24 hours, so taking a new one never loses the previous one.
- The 5 newest are listed in the scissors menu. Click one to copy it again.
- **All Recent Snips…** opens a floating shelf:
  - click a snip to copy it
  - drag it straight into Finder, Mail, Slack, etc.
  - double‑click it to mark it up
  - hover it for Pin / Save / Delete
  - **Save All…** exports every snip to a folder at once

**Copy text from the screen.** Press **⌃⇧T** and drag over any text: an error message, a video, an image, a locked PDF. The text, not a picture, goes to the clipboard. It works offline with Apple's built‑in recognition, including Russian and your other system languages.

**Mark up.** Click the "Copied to clipboard" notification, or the pencil icon, to open the editor:
- Tools: pen, highlighter, arrow, rectangle, text, and pixelate (to hide passwords and personal info), each with 6 colours.
- Every change is copied to the clipboard automatically, so you can just close the editor and paste.
- Shortcuts: ⌘Z undo, ⇧⌘Z redo, ⌘S save, ⌘↩ Done.

**Pin to screen.** Click the pin icon (on the notification, in the editor or on the shelf) to keep a snip floating above all windows.
- Drag it to move it.
- Pinch or press +/− to resize; press 0 for actual size.
- Double‑click or press Esc to close it.
- Right‑click for Copy, Mark Up, Save and Opacity.

## Menu bar options (scissors icon)

- **Snip Shortcut**: ⌃⇧S, ⌥⇧S, ⌘⇧S (replaces "Save As…" in every app) or ⌘⇧2
- **Text Shortcut**: ⌃⇧T, ⌥⇧T or ⌘⇧1
- **Also Save to Pictures › Screenshots**: keeps a PNG copy of every snip
- **Make ⌘⇧3 / ⌘⇧4 Copy to Clipboard Too**: the built‑in macOS shortcuts copy to the clipboard instead of creating files on the Desktop
- **Open at Login**: on by default

## Power use

SnipClip waits on system global hotkeys and does nothing until you press one: no polling and no timers. Measured idle: 0% CPU, 0 wakeups, about 10 MB of memory. Screenshots are taken by macOS's own `screencapture` tool.

## Build / install

```bash
./build.sh install
```

The first time you take a screenshot, macOS asks for **Screen Recording** permission (System Settings › Privacy & Security › Screen & System Audio Recording). Turn it on, then quit and reopen SnipClip. `build.sh` signs the app with a self‑signed "SnipClip Local Signing" certificate from your login keychain, so the permission survives rebuilds. Without that certificate it signs ad‑hoc, and macOS ties the permission to that exact build. In that case, after a rebuild, Settings may still show SnipClip as on while the app asks again. Remove it with the − button and take a snip again.

## License

MIT. See [LICENSE](LICENSE).
