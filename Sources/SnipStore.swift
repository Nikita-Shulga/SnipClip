import AppKit
import ImageIO

/// One screenshot in the recent history, stored as a PNG in ~/Library/Caches.
final class Snip {
    let url: URL
    let date: Date

    init(url: URL, date: Date) {
        self.url = url
        self.date = date
    }

    var name: String { url.deletingPathExtension().lastPathComponent }
    var data: Data? { try? Data(contentsOf: url) }

    lazy var pixelSize: CGSize = {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return .zero }
        return CGSize(width: w, height: h)
    }()

    var caption: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return "\(formatter.string(from: date))  ·  \(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }

    private lazy var thumb: CGImage? = {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }()

    /// A thumbnail whose point size fits inside `box`.
    func thumbnail(fitting box: NSSize) -> NSImage? {
        guard let thumb else { return nil }
        let w = CGFloat(thumb.width), h = CGFloat(thumb.height)
        let s = min(box.width / w, box.height / h)
        return NSImage(cgImage: thumb, size: NSSize(width: (w * s).rounded(), height: (h * s).rounded()))
    }
}

/// The last few screenshots, newest first. Snips older than a day are deleted.
final class SnipStore {
    static let shared = SnipStore()
    static let didChange = Notification.Name("SnipStoreDidChange")

    private let limit = 20
    private let maxAge: TimeInterval = 24 * 60 * 60
    private let fm = FileManager.default
    let directory: URL
    private(set) var snips: [Snip] = []

    private init() {
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("SnipClip/Recent", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        snips = files
            .filter { $0.pathExtension == "png" }
            .map { Snip(url: $0, date: (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.date > $1.date }
        trim()
    }

    /// Moves a freshly captured file into the history.
    @discardableResult
    func add(moving file: URL) -> Snip? {
        let date = Date()
        let dest = SnipStore.uniqueURL(in: directory, name: SnipStore.fileName(for: date))
        do { try fm.moveItem(at: file, to: dest) } catch { return nil }
        return insert(Snip(url: dest, date: date))
    }

    @discardableResult
    func add(data: Data) -> Snip? {
        let date = Date()
        let dest = SnipStore.uniqueURL(in: directory, name: SnipStore.fileName(for: date))
        do { try data.write(to: dest) } catch { return nil }
        return insert(Snip(url: dest, date: date))
    }

    func remove(_ snip: Snip) {
        try? fm.removeItem(at: snip.url)
        snips.removeAll { $0 === snip }
        notify()
    }

    func clear() {
        snips.forEach { try? fm.removeItem(at: $0.url) }
        snips.removeAll()
        notify()
    }

    private func insert(_ snip: Snip) -> Snip {
        snips.insert(snip, at: 0)
        trim()
        notify()
        return snip
    }

    private func trim() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let keep = snips.prefix(limit).filter { $0.date > cutoff }
        for snip in snips where !keep.contains(where: { $0 === snip }) {
            try? fm.removeItem(at: snip.url)
        }
        snips = Array(keep)
    }

    private func notify() {
        NotificationCenter.default.post(name: SnipStore.didChange, object: self)
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }

    /// `dir/name`, or `dir/name (2)` etc. if that file already exists.
    static func uniqueURL(in dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}

enum Clipboard {
    // Kept alive until the next copy; the pasteboard only holds it weakly.
    private static var tiffProvider: TIFFProvider?

    /// Puts a PNG on the clipboard. TIFF is offered too (for older apps) but only
    /// converted if some app actually asks for it.
    static func copyImage(_ png: Data) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        let provider = TIFFProvider(png: png)
        item.setDataProvider(provider, forTypes: [.tiff])
        tiffProvider = provider

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
    let png: Data
    init(png: Data) { self.png = png }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
            item.setData(tiff, forType: type)
        }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}
