import AppKit
import Vision

// MARK: - Pinned screenshot (плавающее окно поверх всех)

final class PinWindow: NSPanel {
    private static var all: [PinWindow] = []
    let image: CGImage
    let scale: CGFloat

    static func show(image: CGImage, scale: CGFloat) {
        let w = PinWindow(image: image, scale: scale)
        all.append(w)
        w.orderFrontRegardless()
        w.makeKey()
    }

    private init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        let screen = NSScreen.underMouse.visibleFrame
        var size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, screen.width * 0.6 / size.width, screen.height * 0.6 / size.height)
        size = NSSize(width: size.width * fit, height: size.height * fit)
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        super.init(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = size
        contentView = PinView(image: image, scale: scale)
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        PinWindow.all.removeAll { $0 === self }
    }
}

private final class PinView: NSView {
    let image: CGImage
    let scale: CGFloat

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        super.init(frame: .zero)
        toolTip = L("Двойной клик — закрыть · колесо — прозрачность · ⌘+колесо — размер · правый клик — меню", "Double-click — close · scroll — opacity · ⌘+scroll — size · right-click — menu")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)
        NSColor(white: 0.5, alpha: 0.5).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.close(); return }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        if event.modifierFlags.contains(.command) {
            let f = 1 + event.scrollingDeltaY * 0.01
            var frame = window.frame
            let newSize = NSSize(width: max(60, frame.width * f), height: max(60, frame.width * f) * frame.height / frame.width)
            frame.origin.x += (frame.width - newSize.width) / 2
            frame.origin.y += (frame.height - newSize.height) / 2
            frame.size = newSize
            window.setFrame(frame, display: true)
        } else {
            window.alphaValue = min(1, max(0.15, window.alphaValue + event.scrollingDeltaY * 0.01))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.close() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": copyImage(); return true
        case "w": window?.close(); return true
        default: return false
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: L("Копировать", "Copy"), action: #selector(copyImage), keyEquivalent: "c")
        m.addItem(withTitle: L("Сохранить", "Save"), action: #selector(saveImage), keyEquivalent: "s")
        m.addItem(withTitle: L("Открыть в редакторе", "Open in editor"), action: #selector(edit), keyEquivalent: "")
        m.addItem(withTitle: L("Исходный размер", "Actual size"), action: #selector(actualSize), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: L("Закрыть", "Close"), action: #selector(closeWindow), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        return m
    }

    @objc private func copyImage() {
        ImageExport.copy(image, scale: scale)
        Toast.show(L("Скопировано в буфер обмена", "Copied to clipboard"))
    }

    @objc private func saveImage() {
        if let url = ImageExport.save(image, scale: scale) { Toast.show(L("Сохранено: \(url.lastPathComponent)", "Saved: \(url.lastPathComponent)")) }
    }

    @objc private func edit() {
        EditorController.open(image: image, scale: scale)
        window?.close()
    }

    @objc private func actualSize() {
        guard let window else { return }
        var f = window.frame
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        f.origin.y += f.height - size.height
        f.size = size
        window.setFrame(f, display: true)
    }

    @objc private func closeWindow() { window?.close() }
}

// MARK: - OCR (Vision) + QR-коды

enum OCR {
    static func recognize(_ image: CGImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            text.automaticallyDetectsLanguage = true
            text.recognitionLanguages = ["ru-RU", "en-US", "uk-UA"]
            let codes = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cgImage: image).perform([text, codes])

            var lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let payloads = (codes.results ?? []).compactMap(\.payloadStringValue)
            if !payloads.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines += payloads
            }
            let result = lines.joined(separator: "\n")
            DispatchQueue.main.async { completion(result) }
        }
    }
}

final class OCRResultPanel: NSPanel {
    private static var current: OCRResultPanel?
    private let textView = NSTextView()

    static func show(text: String, parent: NSWindow?) {
        current?.close()
        if text.isEmpty {
            Toast.show(L("Текст не найден", "No text found"))
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let p = OCRResultPanel(text: text)
        current = p
        if let parent {
            p.setFrameOrigin(NSPoint(x: parent.frame.midX - p.frame.width / 2, y: parent.frame.midY - p.frame.height / 2))
        } else {
            p.center()
        }
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(text: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320), styleMask: [.titled, .closable, .resizable, .utilityWindow],
                   backing: .buffered, defer: false)
        title = L("Распознанный текст — скопирован", "Recognized text — copied")
        isReleasedWhenClosed = false
        level = .floating

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = text
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        let copyButton = NSButton(title: L("Копировать", "Copy"), target: self, action: #selector(copyText))
        copyButton.keyEquivalent = "\r"
        let closeButton = NSButton(title: L("Закрыть", "Close"), target: self, action: #selector(closePanel))
        closeButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), closeButton, copyButton])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [scroll, buttons])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        contentView = stack
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
    }

    @objc private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        Toast.show(L("Текст скопирован", "Text copied"))
        close()
    }

    @objc private func closePanel() { close() }
}
