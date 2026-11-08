import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Shortcut presets

struct Shortcut {
    let key: String
    let keyCode: Int
    let flags: NSEvent.ModifierFlags
    var note: String? = nil

    var title: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }

    var carbonModifiers: UInt32 {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        return UInt32(m)
    }
}

let snipShortcuts = [
    Shortcut(key: "s", keyCode: kVK_ANSI_S, flags: [.control, .shift]),
    Shortcut(key: "s", keyCode: kVK_ANSI_S, flags: [.option, .shift]),
    Shortcut(key: "s", keyCode: kVK_ANSI_S, flags: [.command, .shift], note: "replaces “Save As…” in every app"),
    Shortcut(key: "2", keyCode: kVK_ANSI_2, flags: [.command, .shift]),
]

let textShortcuts = [
    Shortcut(key: "t", keyCode: kVK_ANSI_T, flags: [.control, .shift]),
    Shortcut(key: "t", keyCode: kVK_ANSI_T, flags: [.option, .shift]),
    Shortcut(key: "1", keyCode: kVK_ANSI_1, flags: [.command, .shift]),
]

enum Keys {
    static let shortcut = "shortcutIndex"
    static let textShortcut = "textShortcutIndex"
    static let saveCopy = "saveCopyToPictures"
    static let didFirstLaunch = "didFirstLaunch"
}

enum HotKey: UInt32 {
    case snip = 1, text = 2
}

// Carbon calls this on the main thread whenever a registered hotkey is pressed.
private func hotKeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    if status == noErr, let hotKey = HotKey(rawValue: id.id) {
        AppDelegate.shared?.capture(hotKey == .snip ? .area : .text)
    }
    return noErr
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    enum Capture { case area, fullScreen, text }

    private let defaults = UserDefaults.standard
    private let store = SnipStore.shared
    private var statusItem: NSStatusItem!
    private var hotKeyRefs: [HotKey: EventHotKeyRef] = [:]
    private var captureProcess: Process?

    private func shortcut(_ hotKey: HotKey) -> Shortcut {
        let (list, key) = hotKey == .snip ? (snipShortcuts, Keys.shortcut) : (textShortcuts, Keys.textShortcut)
        let i = defaults.integer(forKey: key)
        return list.indices.contains(i) ? list[i] : list[0]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        defaults.register(defaults: [Keys.shortcut: 0, Keys.textShortcut: 0, Keys.saveCopy: false])

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
        registerHotKey(.snip)
        registerHotKey(.text)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnipClip")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NSLog("SnipClip launched; screen recording preflight=%d live=%d",
              CGPreflightScreenCaptureAccess() ? 1 : 0, screenPermissionGranted ? 1 : 0)

        if !defaults.bool(forKey: Keys.didFirstLaunch) {
            defaults.set(true, forKey: Keys.didFirstLaunch)
            try? SMAppService.mainApp.register()
            if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
            Toast.show("SnipClip is running", detail: "Press \(shortcut(.snip).title) to take a snip")
        }
    }

    // MARK: Hotkeys

    private func registerHotKey(_ hotKey: HotKey) {
        if let ref = hotKeyRefs.removeValue(forKey: hotKey) { UnregisterEventHotKey(ref) }
        let s = shortcut(hotKey)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x534E_4950), id: hotKey.rawValue) // 'SNIP'
        let status = RegisterEventHotKey(UInt32(s.keyCode), s.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs[hotKey] = ref
        } else {
            alert("Couldn’t use \(s.title)",
                  "Another app already owns this shortcut. Pick a different one from the SnipClip menu.")
        }
    }

    // MARK: Capture

    func capture(_ kind: Capture) {
        guard captureProcess == nil, hasScreenPermission() else { return }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("snipclip-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive (drag a region, Space for a window, Esc to cancel)  -x: no shutter sound
        switch kind {
        case .area: process.arguments = ["-i", file.path]
        case .fullScreen: process.arguments = [file.path]
        case .text: process.arguments = ["-i", "-x", file.path]
        }
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.captureProcess = nil
                guard FileManager.default.fileExists(atPath: file.path) else { return } // cancelled
                if kind == .text { self.recognizeText(in: file) } else { self.didCapture(file) }
            }
        }
        do {
            try process.run()
            captureProcess = process
        } catch {
            NSSound.beep()
        }
    }

    private func didCapture(_ file: URL) {
        guard let snip = store.add(moving: file), let png = snip.data else { return }
        Clipboard.copyImage(png)
        var detail = "Press ⌘V to paste · click to mark up"
        if defaults.bool(forKey: Keys.saveCopy), saveToPictures(snip) {
            detail = "Also saved to Pictures › Screenshots"
        }
        Toast.show("Copied to clipboard", detail: detail, snip: snip)
    }

    private func recognizeText(in file: URL) {
        TextRecognizer.recognize(file) { text in
            try? FileManager.default.removeItem(at: file)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Toast.show("No text found", detail: "Try selecting the text more closely")
            } else {
                Clipboard.copyText(trimmed)
                Toast.show("Text copied", detail: trimmed.replacingOccurrences(of: "\n", with: " "))
            }
        }
    }

    private func saveToPictures(_ snip: Snip) -> Bool {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let dir = pictures.appendingPathComponent("Screenshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: snip.url, to: SnipStore.uniqueURL(in: dir, name: snip.url.lastPathComponent))
            return true
        } catch {
            return false
        }
    }

    /// CGPreflightScreenCaptureAccess() keeps answering "no" until the app restarts, even after
    /// the user grants access. Window titles of other apps are only visible with the permission,
    /// so they give a live answer.
    private var screenPermissionGranted: Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        return windows.contains { info in
            (info[kCGWindowOwnerPID] as? Int32) != me
                && (info[kCGWindowOwnerName] as? String) != "Dock"
                && (info[kCGWindowLayer] as? Int) == 0
                && !((info[kCGWindowName] as? String) ?? "").isEmpty
        }
    }

    private func hasScreenPermission() -> Bool {
        if screenPermissionGranted { return true }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "SnipClip needs Screen Recording permission"
        a.informativeText = "Without it, screenshots only show your wallpaper.\n\nTurn on SnipClip in System Settings › Privacy & Security › Screen & System Audio Recording.\n\nIf SnipClip isn’t in the list, click + and choose SnipClip from Applications."
        a.addButton(withTitle: "Open System Settings")
        a.addButton(withTitle: "Capture Anyway")
        a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            // Asking macOS for access is what puts SnipClip (back) into the Settings list.
            CGRequestScreenCaptureAccess()
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: Snip actions (used by the menu, toast, shelf and pins)

    func copy(_ snip: Snip) {
        guard let png = snip.data else { return }
        Clipboard.copyImage(png)
        Toast.show("Copied to clipboard", detail: "Press ⌘V to paste")
    }

    func markUp(_ snip: Snip) {
        guard let png = snip.data else { return }
        EditorController.open(png: png, name: snip.name)
    }

    func pin(_ snip: Snip) {
        guard let png = snip.data else { return }
        PinWindow.show(png: png)
    }

    func save(_ snip: Snip) {
        guard let png = snip.data else { return }
        save(png: png, name: snip.url.lastPathComponent)
    }

    func save(png: Data, name: String, in window: NSWindow? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let write = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do { try png.write(to: url) } catch { self.alert("Couldn’t save the snip", error.localizedDescription) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: write) } else { write(panel.runModal()) }
    }

    func saveAll() {
        let snips = store.snips
        guard !snips.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder for \(snips.count) snip\(snips.count == 1 ? "" : "s")"
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        var saved = 0
        for snip in snips.reversed() {
            let dest = SnipStore.uniqueURL(in: dir, name: snip.url.lastPathComponent)
            if (try? FileManager.default.copyItem(at: snip.url, to: dest)) != nil { saved += 1 }
        }
        Toast.show("Saved \(saved) snip\(saved == 1 ? "" : "s")", detail: (dir.path as NSString).abbreviatingWithTildeInPath)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let area = item("Capture Area", #selector(captureArea))
        let text = item("Copy Text from Screen", #selector(captureText))
        for (menuItem, s) in [(area, shortcut(.snip)), (text, shortcut(.text))] {
            menuItem.keyEquivalent = s.key
            menuItem.keyEquivalentModifierMask = s.flags
        }
        menu.addItem(area)
        menu.addItem(text)
        menu.addItem(item("Capture Full Screen", #selector(captureFullScreen)))

        menu.addItem(.separator())
        let recent = store.snips.prefix(5)
        if !recent.isEmpty {
            menu.addItem(header("Recent — click to copy again"))
            for snip in recent {
                let entry = item(snip.caption, #selector(copyRecent(_:)))
                entry.representedObject = snip
                entry.image = snip.thumbnail(fitting: NSSize(width: 44, height: 28))
                menu.addItem(entry)
            }
        }
        menu.addItem(item(store.snips.isEmpty ? "Recent Snips…" : "All Recent Snips (\(store.snips.count))…",
                          #selector(showShelf)))

        menu.addItem(.separator())
        menu.addItem(shortcutMenu("Snip Shortcut", snipShortcuts, selected: shortcut(.snip), action: #selector(chooseSnipShortcut(_:))))
        menu.addItem(shortcutMenu("Text Shortcut", textShortcuts, selected: shortcut(.text), action: #selector(chooseTextShortcut(_:))))

        let save = item("Also Save to Pictures › Screenshots", #selector(toggleSaveCopy))
        save.state = defaults.bool(forKey: Keys.saveCopy) ? .on : .off
        menu.addItem(save)

        let native = item("Make ⌘⇧3 / ⌘⇧4 Copy to Clipboard Too", #selector(toggleNativeClipboard))
        native.state = nativeScreenshotsGoToClipboard ? .on : .off
        menu.addItem(native)

        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SnipClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return .sectionHeader(title: title) }
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func shortcutMenu(_ title: String, _ list: [Shortcut], selected: Shortcut, action: Selector) -> NSMenuItem {
        let submenu = NSMenu()
        for (i, s) in list.enumerated() {
            let entry = item(s.note.map { "\(s.title)   (\($0))" } ?? s.title, action)
            entry.tag = i
            entry.state = s.title == selected.title ? .on : .off
            submenu.addItem(entry)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    // Let the menu finish closing before the crosshair appears.
    @objc private func captureArea() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.capture(.area) }
    }

    @objc private func captureText() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.capture(.text) }
    }

    @objc private func captureFullScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.capture(.fullScreen) }
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        if let snip = sender.representedObject as? Snip { copy(snip) }
    }

    @objc private func showShelf() { ShelfController.shared.show() }

    @objc private func chooseSnipShortcut(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: Keys.shortcut)
        registerHotKey(.snip)
    }

    @objc private func chooseTextShortcut(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: Keys.textShortcut)
        registerHotKey(.text)
    }

    @objc private func toggleSaveCopy() {
        defaults.set(!defaults.bool(forKey: Keys.saveCopy), forKey: Keys.saveCopy)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            alert("Couldn’t change Open at Login", error.localizedDescription)
        }
    }

    // MARK: Built-in macOS screenshots

    private var nativeScreenshotsGoToClipboard: Bool {
        CFPreferencesCopyAppValue("target" as CFString, "com.apple.screencapture" as CFString) as? String == "clipboard"
    }

    @objc private func toggleNativeClipboard() {
        if nativeScreenshotsGoToClipboard {
            run("/usr/bin/defaults", ["delete", "com.apple.screencapture", "target"])
        } else {
            run("/usr/bin/defaults", ["write", "com.apple.screencapture", "target", "clipboard"])
        }
        run("/usr/bin/killall", ["SystemUIServer"])
    }

    private func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }

    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
