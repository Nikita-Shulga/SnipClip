import AppKit

/// A button that reacts to the first click even when its window isn't key
/// (needed for toasts, pins and the shelf, which never activate the app).
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

func symbolButton(_ symbol: String, _ tip: String, _ target: AnyObject, _ action: Selector, size: CGFloat = 13) -> NSButton {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
    let button = FirstMouseButton(image: image ?? NSImage(), target: target, action: action)
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.toolTip = tip
    return button
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
}

func circleImage(_ color: NSColor, diameter: CGFloat = 14) -> NSImage {
    NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        color.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 1
        path.stroke()
        return true
    }
}

/// Stretchable rounded-rect mask, the reliable way to round an NSVisualEffectView.
func roundedMask(radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
}

func screenUnderMouse() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
}

func pinEdges(_ view: NSView, to container: NSView, inset: CGFloat = 0) {
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
        view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
        view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
    ])
}
