import AppKit

/// A small notification in the bottom-right corner, like Windows' "Snip copied to clipboard".
/// For a screenshot it shows a thumbnail; clicking it opens the markup editor.
final class Toast: NSObject {
    private static var current: Toast?

    private let panel: NSPanel
    private let snip: Snip?
    private var hideWork: DispatchWorkItem?

    static func show(_ title: String, detail: String? = nil, snip: Snip? = nil) {
        current?.close()
        let toast = Toast(title: title, detail: detail, snip: snip)
        current = toast
        toast.present()
    }

    private init(title: String, detail: String?, snip: Snip?) {
        self.snip = snip
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()

        let content = ToastView()
        content.onClick = { [weak self] in self?.clicked() }
        content.onHover = { [weak self] inside in
            if inside { self?.hideWork?.cancel() } else { self?.scheduleHide(after: 1.5) }
        }

        var views: [NSView] = []
        if let thumb = snip?.thumbnail(fitting: NSSize(width: 72, height: 48)) {
            let imageView = NSImageView(image: thumb)
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 4
            imageView.layer?.masksToBounds = true
            imageView.widthAnchor.constraint(equalToConstant: thumb.size.width).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: thumb.size.height).isActive = true
            views.append(imageView)
        }

        let texts = NSStackView(views: [label(title, size: 13, weight: .semibold, color: .white)])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        if let detail {
            let line = label(detail, size: 11.5, color: NSColor.white.withAlphaComponent(0.7))
            line.lineBreakMode = .byTruncatingTail
            line.maximumNumberOfLines = 1
            line.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            line.widthAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true
            texts.addArrangedSubview(line)
        }
        views.append(texts)

        if snip != nil {
            for button in [symbolButton("pencil.tip.crop.circle", "Mark up", self, #selector(markUp), size: 16),
                           symbolButton("pin", "Pin to screen", self, #selector(pinIt), size: 15)] {
                button.contentTintColor = .white
                views.append(button)
            }
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        content.addSubview(stack)
        pinEdges(stack, to: content, inset: 11)
        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)

        panel.contentView = content
        panel.setContentSize(size)
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    private func present() {
        if let frame = screenUnderMouse()?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.minY + 16))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        scheduleHide(after: snip == nil ? 2.2 : 4)
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func close() {
        hideWork?.cancel()
        if Toast.current === self { Toast.current = nil }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
            self.panel.orderOut(nil)
        }
    }

    private func clicked() {
        if let snip { AppDelegate.shared?.markUp(snip) }
        close()
    }

    @objc private func markUp() { clicked() }

    @objc private func pinIt() {
        if let snip { AppDelegate.shared?.pin(snip) }
        close()
    }
}

private final class ToastView: NSVisualEffectView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        maskImage = roundedMask(radius: 12)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
