import AppKit
import CoreImage

// MARK: - Model

enum Tool: Int, CaseIterable {
    case pen, highlighter, arrow, rectangle, text, pixelate

    var symbol: String {
        ["pencil.tip", "highlighter", "arrow.up.right", "rectangle", "textformat", "checkerboard.rectangle"][rawValue]
    }

    var tip: String {
        ["Pen", "Highlighter", "Arrow", "Rectangle", "Text", "Pixelate (hide passwords and personal info)"][rawValue]
    }

    /// Line width (or font size for text), in points.
    var size: CGFloat { [3, 18, 4, 3, 22, 0][rawValue] }
}

/// One drawn mark, stored in image pixel coordinates (origin bottom-left).
struct Annotation {
    var tool: Tool
    var points: [CGPoint]
    var color: NSColor
    var size: CGFloat
    var text = ""

    var rect: CGRect {
        let a = points[0], b = points[points.count - 1]
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var isMeaningful: Bool {
        switch tool {
        case .pen, .highlighter, .text: return true
        case .arrow: return hypot(rect.width, rect.height) > 4
        case .rectangle, .pixelate: return rect.width > 2 && rect.height > 2
        }
    }
}

let palette: [NSColor] = [
    NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1),
    NSColor(srgbRed: 1, green: 0.84, blue: 0, alpha: 1),
    NSColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1),
    NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1),
    NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
]

// MARK: - Canvas

final class CanvasView: NSView, NSTextFieldDelegate {
    let image: CGImage
    let scale: CGFloat // image pixels per point (2 on Retina)
    var tool: Tool = .pen { didSet { window?.invalidateCursorRects(for: self) } }
    var color = palette[0]
    var onChange: (() -> Void)?

    private(set) var annotations: [Annotation] = []
    private var current: Annotation?
    private var textField: NSTextField?
    private var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }

    private lazy var pixellated: CGImage? = {
        let block = max(12 * scale, CGFloat(max(image.width, image.height)) / 80)
        let input = CIImage(cgImage: image)
        // Blur first so each block shows the area's average colour, not one sampled pixel.
        let output = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: block / 2])
            .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: block, kCIInputCenterKey: CIVector(x: 0, y: 0)])
            .cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)
    }()

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        super.init(frame: .zero)
        // Since macOS 14 views don't clip by default, and the background fill would cover the toolbar.
        if #available(macOS 14.0, *) { clipsToBounds = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// Where the image is drawn: fitted into the view, never larger than its real size.
    private var imageRect: NSRect {
        let area = bounds.insetBy(dx: 16, dy: 16)
        let w = pixelSize.width / scale, h = pixelSize.height / scale
        let s = max(0.01, min(area.width / w, area.height / h, 1))
        return NSRect(x: (bounds.midX - w * s / 2).rounded(), y: (bounds.midY - h * s / 2).rounded(), width: w * s, height: h * s)
    }

    private func imagePoint(_ viewPoint: NSPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: (viewPoint.x - r.minX) * pixelSize.width / r.width,
                       y: (viewPoint.y - r.minY) * pixelSize.height / r.height)
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: tool == .text ? .iBeam : .crosshair)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = imageRect

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 8, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        NSColor.white.setFill()
        r.fill()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: r.width / pixelSize.width, y: r.height / pixelSize.height)
        render(in: ctx, including: current)
        ctx.restoreGState()
    }

    private func render(in ctx: CGContext, including extra: Annotation? = nil) {
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: pixelSize))
        for a in annotations { draw(a, in: ctx) }
        if let extra { draw(extra, in: ctx) }
    }

    private func draw(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(a.size)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)

        switch a.tool {
        case .pen, .highlighter:
            if a.tool == .highlighter {
                ctx.setBlendMode(.multiply)
                ctx.setStrokeColor(a.color.withAlphaComponent(0.85).cgColor)
            }
            ctx.move(to: a.points[0])
            for p in a.points.dropFirst() { ctx.addLine(to: p) }
            if a.points.count == 1 { ctx.addLine(to: a.points[0]) } // a dot
            ctx.strokePath()

        case .rectangle:
            ctx.stroke(a.rect)

        case .arrow:
            let s = a.points[0], e = a.points[a.points.count - 1]
            let length = hypot(e.x - s.x, e.y - s.y)
            guard length > 0.5 else { return }
            let ux = (e.x - s.x) / length, uy = (e.y - s.y) / length
            let head = min(a.size * 4.5, length * 0.8)
            let half = head * 0.55
            let base = CGPoint(x: e.x - ux * head, y: e.y - uy * head)
            ctx.move(to: s)
            ctx.addLine(to: CGPoint(x: e.x - ux * head * 0.6, y: e.y - uy * head * 0.6))
            ctx.strokePath()
            ctx.move(to: e)
            ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            ctx.closePath()
            ctx.fillPath()

        case .text:
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: a.size),
                                                             .foregroundColor: a.color]
            NSAttributedString(string: a.text, attributes: attributes).draw(at: a.points[0])

        case .pixelate:
            ctx.clip(to: a.rect)
            if let pixellated {
                ctx.draw(pixellated, in: CGRect(origin: .zero, size: pixelSize))
            } else {
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(a.rect)
            }
        }
    }

    /// The marked-up image as PNG, at full resolution and with Retina DPI preserved.
    func renderPNG() -> Data? {
        let w = image.width, h = image.height
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? srgb
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
            ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        render(in: ctx)
        NSGraphicsContext.restoreGraphicsState()

        guard let output = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: output)
        rep.size = NSSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if textField != nil {
            window?.makeFirstResponder(self) // finishes the text being typed
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        if tool == .text {
            beginText(at: viewPoint)
            return
        }
        current = Annotation(tool: tool, points: [imagePoint(viewPoint)], color: color, size: tool.size * scale)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var a = current else { return }
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        if a.tool == .pen || a.tool == .highlighter || a.points.count == 1 {
            a.points.append(p)
        } else {
            a.points[a.points.count - 1] = p
        }
        current = a
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let a = current else { return }
        current = nil
        if a.isMeaningful { add(a) } else { needsDisplay = true }
    }

    // MARK: Text

    private var viewScale: CGFloat { imageRect.width / pixelSize.width }

    private func beginText(at viewPoint: NSPoint) {
        let field = NSTextField(string: "")
        field.font = .boldSystemFont(ofSize: Tool.text.size * scale * viewScale)
        field.textColor = color
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.placeholderString = "Type here"
        field.delegate = self
        field.sizeToFit()
        field.frame = NSRect(x: viewPoint.x - 2, y: viewPoint.y - field.frame.height / 2,
                             width: max(80, field.frame.width), height: field.frame.height)
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = textField else { return }
        let origin = field.frame.origin
        field.sizeToFit()
        field.setFrameOrigin(origin)
        field.setFrameSize(NSSize(width: max(80, field.frame.width + 8), height: field.frame.height))
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        let origin = imagePoint(NSPoint(x: field.frame.minX + 2, y: field.frame.minY))
        let color = field.textColor ?? color
        field.removeFromSuperview()
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            add(Annotation(tool: .text, points: [origin], color: color, size: Tool.text.size * scale, text: text))
        }
    }

    // MARK: Undo

    private func add(_ a: Annotation) {
        annotations.append(a)
        undoManager?.registerUndo(withTarget: self) { $0.removeLast() }
        changed()
    }

    private func removeLast() {
        guard let a = annotations.popLast() else { return }
        undoManager?.registerUndo(withTarget: self) { $0.add(a) }
        changed()
    }

    private func changed() {
        needsDisplay = true
        onChange?()
    }
}

// MARK: - Window

final class EditorWindow: NSWindow {
    /// The app has no menu bar of its own, so map the usual shortcuts here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
            let shift = flags.contains(.shift)
            let action: Selector? = switch key {
            case "z": shift ? #selector(EditorController.redo(_:)) : #selector(EditorController.undo(_:))
            case "x": #selector(NSText.cut(_:))
            case "c": #selector(NSText.copy(_:))
            case "v": #selector(NSText.paste(_:))
            case "a": #selector(NSText.selectAll(_:))
            case "s": #selector(EditorController.saveDocument(_:))
            case "w": #selector(NSWindow.performClose(_:))
            case "\r": #selector(EditorController.done(_:))
            default: nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class EditorController: NSWindowController, NSWindowDelegate {
    private static var editors: [EditorController] = []

    private let canvas: CanvasView
    private let name: String
    private var edited = false
    private var copyWork: DispatchWorkItem?
    private var toolColors: [Tool: NSColor] = [.highlighter: palette[1]]
    private var toolControl: NSSegmentedControl!
    private var colorControl: NSSegmentedControl!

    static func open(png: Data, name: String) {
        guard let rep = NSBitmapImageRep(data: png), let image = rep.cgImage else { return }
        let scale = max(1, (CGFloat(rep.pixelsWide) / rep.size.width).rounded())
        let editor = EditorController(image: image, scale: scale, name: name)
        editors.append(editor)
        NSApp.activate(ignoringOtherApps: true)
        editor.window?.center()
        editor.showWindow(nil)
        editor.window?.makeFirstResponder(editor.canvas)
    }

    private init(image: CGImage, scale: CGFloat, name: String) {
        canvas = CanvasView(image: image, scale: scale)
        self.name = name

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = CGFloat(image.width) / scale, h = CGFloat(image.height) / scale
        let s = min(1, visible.width * 0.85 / (w + 32), (visible.height * 0.85 - 52) / (h + 32))
        let size = NSSize(width: max(820, w * s + 32), height: max(360, h * s + 32 + 52))
        let window = EditorWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        window.title = "Mark Up — \(name)"
        window.minSize = NSSize(width: 820, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        canvas.onChange = { [weak self] in self?.changed() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        toolControl = NSSegmentedControl(images: Tool.allCases.map {
            NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.tip) ?? NSImage()
        }, trackingMode: .selectOne, target: self, action: #selector(toolChanged))
        Tool.allCases.forEach { toolControl.setToolTip($0.tip, forSegment: $0.rawValue) }
        toolControl.selectedSegment = 0

        colorControl = NSSegmentedControl(images: palette.map { circleImage($0) }, trackingMode: .selectOne,
                                          target: self, action: #selector(colorChanged))
        colorControl.selectedSegment = 0

        let undo = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")!,
                            target: self, action: #selector(undo(_:)))
        undo.toolTip = "Undo (⌘Z)"

        let pin = NSButton(title: "Pin", image: NSImage(systemSymbolName: "pin", accessibilityDescription: nil)!,
                           target: self, action: #selector(pinToScreen))
        pin.toolTip = "Keep this snip floating on top of all windows"
        let save = NSButton(title: "Save…", target: self, action: #selector(saveDocument(_:)))
        let done = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        done.keyEquivalent = "\r"
        done.keyEquivalentModifierMask = .command
        done.bezelColor = .controlAccentColor
        done.toolTip = "Copy to clipboard and close (⌘↩)"

        let bar = NSStackView()
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        bar.spacing = 10
        for view in [toolControl!, colorControl!, undo] as [NSView] { bar.addView(view, in: .leading) }
        for view in [pin, save, done] { bar.addView(view, in: .trailing) }

        let divider = NSBox()
        divider.boxType = .separator

        let root = NSView()
        for view in [bar, divider, canvas] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 50),
            divider.topAnchor.constraint(equalTo: bar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: divider.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window?.contentView = root
    }

    // MARK: Toolbar

    @objc private func toolChanged() {
        let tool = Tool(rawValue: toolControl.selectedSegment) ?? .pen
        canvas.tool = tool
        let color = toolColors[tool] ?? palette[0]
        canvas.color = color
        colorControl.selectedSegment = palette.firstIndex(of: color) ?? 0
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorChanged() {
        let color = palette[colorControl.selectedSegment]
        toolColors[canvas.tool] = color
        canvas.color = color
    }

    @objc func undo(_ sender: Any?) {
        if let manager = window?.undoManager, manager.canUndo { manager.undo() }
    }

    @objc func redo(_ sender: Any?) {
        if let manager = window?.undoManager, manager.canRedo { manager.redo() }
    }

    @objc func copy(_ sender: Any?) {
        guard let png = canvas.renderPNG() else { return }
        Clipboard.copyImage(png)
        Toast.show("Copied to clipboard", detail: "Press ⌘V to paste")
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let png = canvas.renderPNG() else { return }
        AppDelegate.shared?.save(png: png, name: "\(name).png", in: window)
    }

    @objc func done(_ sender: Any?) {
        window?.makeFirstResponder(nil) // commit any text being typed
        copyWork?.cancel()
        copy(sender)
        window?.close()
    }

    @objc private func pinToScreen() {
        guard let png = canvas.renderPNG() else { return }
        PinWindow.show(png: png)
    }

    // Like Windows' Snipping Tool, every change is copied to the clipboard automatically.
    private func changed() {
        edited = true
        copyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if let png = self?.canvas.renderPNG() { Clipboard.copyImage(png) }
        }
        copyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func windowWillClose(_ notification: Notification) {
        copyWork?.cancel()
        window?.makeFirstResponder(nil) // commit any text being typed
        if edited, let png = canvas.renderPNG() {
            Clipboard.copyImage(png)
            SnipStore.shared.add(data: png)
        }
        DispatchQueue.main.async { EditorController.editors.removeAll { $0 === self } }
    }
}
