import AppKit

/// The "Recent Snips" window: click a snip to copy it again, drag it into any app,
/// double-click to mark it up, or save them all at once.
final class ShelfController: NSObject {
    static let shared = ShelfController()

    private var panel: NSPanel?
    private let list = NSStackView()
    private let countLabel = label("", size: 12, weight: .medium, color: .secondaryLabelColor)
    private let emptyLabel = label("No snips yet.\nTake one and it shows up here.", size: 13, color: .secondaryLabelColor)
    private var saveAllButton: NSButton!
    private var clearButton: NSButton!

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: SnipStore.didChange, object: nil)
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        reload()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Recent Snips"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 240, height: 280)
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 316, y: frame.maxY - 16))
        }

        saveAllButton = NSButton(title: "Save All…", target: self, action: #selector(saveAll))
        clearButton = NSButton(title: "Clear", target: self, action: #selector(clear))
        for button in [saveAllButton!, clearButton!] { button.controlSize = .small }
        let header = NSStackView()
        header.addView(countLabel, in: .leading)
        header.addView(saveAllButton, in: .trailing)
        header.addView(clearButton, in: .trailing)

        let hint = label("Click to copy · double-click to mark up · drag into any app",
                         size: 11, color: .tertiaryLabelColor)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        list.orientation = .vertical
        list.spacing = 10
        let document = FlippedView()
        document.addSubview(list)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 2

        let root = NSView()
        for view in [header, hint, scroll, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        document.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            hint.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        panel.contentView = root
        return panel
    }

    @objc private func reload() {
        guard panel != nil else { return }
        let snips = SnipStore.shared.snips
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for snip in snips {
            let cell = SnipCellView(snip: snip)
            list.addArrangedSubview(cell)
            cell.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        countLabel.stringValue = snips.count == 1 ? "1 snip" : "\(snips.count) snips"
        emptyLabel.isHidden = !snips.isEmpty
        saveAllButton.isEnabled = !snips.isEmpty
        clearButton.isEnabled = !snips.isEmpty
    }

    @objc private func saveAll() { AppDelegate.shared?.saveAll() }
    @objc private func clear() { SnipStore.shared.clear() }
}

private final class SnipCellView: NSView, NSDraggingSource {
    private let snip: Snip
    private let imageView = NSImageView()
    private let actions = NSVisualEffectView()
    private var mouseDownEvent: NSEvent?
    private var dragging = false
    private var hovered = false { didSet { needsDisplay = true; actions.isHidden = !hovered } }

    init(snip: Snip) {
        self.snip = snip
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = snip.name

        imageView.image = snip.thumbnail(fitting: NSSize(width: 520, height: 300))
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let caption = label(snip.caption, size: 11, color: .secondaryLabelColor)

        let buttons = NSStackView(views: [
            symbolButton("doc.on.doc", "Copy", self, #selector(copySnip)),
            symbolButton("pencil.tip.crop.circle", "Mark up", self, #selector(markUp)),
            symbolButton("pin", "Pin to screen", self, #selector(pinSnip)),
            symbolButton("square.and.arrow.down", "Save as…", self, #selector(save)),
            symbolButton("trash", "Delete", self, #selector(delete)),
        ])
        buttons.spacing = 10
        buttons.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        actions.material = .hudWindow
        actions.state = .active
        actions.appearance = NSAppearance(named: .vibrantDark)
        actions.maskImage = roundedMask(radius: 8)
        actions.isHidden = true
        actions.addSubview(buttons)
        pinEdges(buttons, to: actions)

        for view in [imageView, caption, actions] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.heightAnchor.constraint(equalToConstant: 140),
            caption.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            actions.centerXAnchor.constraint(equalTo: centerXAnchor),
            actions.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = (hovered ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25)
                                          : NSColor.quaternaryLabelColor).cgColor
    }

    // Clicks anywhere except the action buttons belong to the cell.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let view = super.hitTest(point) else { return nil }
        return view is NSButton ? view : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let down = mouseDownEvent else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        guard hypot(a.x - b.x, a.y - b.y) > 4 else { return }
        dragging = true

        let item = NSDraggingItem(pasteboardWriter: snip.url as NSURL)
        var frame = imageView.frame
        if let image = imageView.image {
            let s = min(frame.width / image.size.width, frame.height / image.size.height, 1)
            let size = NSSize(width: image.size.width * s, height: image.size.height * s)
            frame = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        }
        item.setDraggingFrame(frame, contents: imageView.image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !dragging else { return }
        if event.clickCount == 2 { markUp() } else if event.clickCount == 1 { copySnip() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("Copy", #selector(copySnip)), ("Mark Up…", #selector(markUp)),
                                ("Pin to Screen", #selector(pinSnip)), ("Save As…", #selector(save))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(delete), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copySnip() { AppDelegate.shared?.copy(snip) }
    @objc private func markUp() { AppDelegate.shared?.markUp(snip) }
    @objc private func pinSnip() { AppDelegate.shared?.pin(snip) }
    @objc private func save() { AppDelegate.shared?.save(snip) }
    @objc private func delete() { SnipStore.shared.remove(snip) }
}
