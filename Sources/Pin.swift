import AppKit

/// A snip floating above all windows. Drag to move, pinch or +/− to resize,
/// double-click or Esc to close, right-click for more.
final class PinWindow: NSPanel {
    private static var pins: [PinWindow] = []

    private let png: Data
    private let imageSize: NSSize

    static func show(png: Data) {
        guard let image = NSImage(data: png) else { return }
        let pin = PinWindow(png: png, image: image)
        pins.append(pin)
        pin.orderFrontRegardless()
        pin.makeKey()
    }

    private init(png: Data, image: NSImage) {
        self.png = png
        imageSize = image.size

        let visible = screenUnderMouse()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let s = min(1, visible.width * 0.6 / image.size.width, visible.height * 0.6 / image.size.height)
        let size = NSSize(width: image.size.width * s, height: image.size.height * s)
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: min(max(mouse.x - size.width / 2, visible.minX), visible.maxX - size.width),
                             y: min(max(mouse.y - size.height / 2, visible.minY), visible.maxY - size.height))

        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = image.size
        minSize = NSSize(width: 60, height: 60)
        contentView = PinView(image: image)
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        PinWindow.pins.removeAll { $0 === self }
    }

    func scale(by factor: CGFloat) {
        let w = min(max(frame.width * factor, 60), imageSize.width * 4)
        let h = w * imageSize.height / imageSize.width
        setFrame(NSRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h), display: true)
        invalidateShadow()
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\u{1b}": close()
        case "=", "+": scale(by: 1.15)
        case "-": scale(by: 1 / 1.15)
        case "0": actualSize()
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "c": copyImage(); return true
        case "w": close(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("Copy", #selector(copyImage)), ("Mark Up…", #selector(markUp)),
                                ("Save As…", #selector(saveImage)), ("Actual Size", #selector(actualSize))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        let opacity = NSMenu()
        for percent in [100, 80, 60, 40] {
            let entry = opacity.addItem(withTitle: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = percent
            entry.state = Int((alphaValue * 100).rounded()) == percent ? .on : .off
        }
        menu.addItem(withTitle: "Opacity", action: nil, keyEquivalent: "").submenu = opacity
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyImage() {
        Clipboard.copyImage(png)
        Toast.show("Copied to clipboard", detail: "Press ⌘V to paste")
    }

    @objc private func markUp() { EditorController.open(png: png, name: "Pinned Snip") }
    @objc private func saveImage() { AppDelegate.shared?.save(png: png, name: SnipStore.fileName(for: Date())) }
    @objc private func setOpacity(_ sender: NSMenuItem) { alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func closePin() { close() }

    @objc private func actualSize() {
        setFrame(NSRect(x: frame.midX - imageSize.width / 2, y: frame.midY - imageSize.height / 2,
                        width: imageSize.width, height: imageSize.height), display: true)
        invalidateShadow()
    }
}

private final class PinView: NSView {
    private let image: NSImage
    private var closeButton: NSButton!

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
        toolTip = "Drag to move · pinch or +/− to resize · double-click to close · right-click for more"

        closeButton = symbolButton("xmark.circle.fill", "Close", self, #selector(closePin), size: 18)
        closeButton.contentTintColor = NSColor.black.withAlphaComponent(0.65)
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.close()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        (window as? PinWindow)?.scale(by: 1 + event.magnification)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        (window as? PinWindow)?.contextMenu()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    @objc private func closePin() { window?.close() }
}
