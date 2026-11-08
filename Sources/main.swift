// SnipClip — a tiny menu bar app that works like Windows 11's Win+Shift+S:
// press a shortcut, drag a region, and the screenshot lands on the clipboard
// ready for ⌘V.
//
// Power use: the app sits idle on Carbon global hotkeys (event driven, no
// polling, no timers). The capture itself is done by the system's own
// /usr/sbin/screencapture tool, which only runs while you take a screenshot.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
