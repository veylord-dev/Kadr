import AppKit
import UniformTypeIdentifiers

// MARK: - Editor window

final class EditorController: NSWindowController, NSWindowDelegate {
    private static var open: [EditorController] = []

    private struct Snapshot { let base: CGImage; let annotations: [Annotation] }

    private(set) var base: CGImage
    let scale: CGFloat
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var savedURL: URL?

    let canvas: CanvasView
    private let scrollView = NSScrollView()
    private let toolControl = NSSegmentedControl()
    private let colorWell = NSColorWell(style: .minimal)
    private let widthControl = NSSegmentedControl()
    private var swatchButtons: [NSButton] = []
    private static let widths: [CGFloat] = [2, 4, 6, 10]
    private let statusLabel = NSTextField(labelWithString: "")
    private let swatch = NSView()

    var tool: Tool = .arrow { didSet { toolControl.selectedSegment = tool.rawValue; canvas.toolChanged() } }
    var color: NSColor { colorWell.color }
    var lineWidth: CGFloat { Self.widths[max(0, widthControl.selectedSegment)] }

    static let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue,
                                     .systemPurple, .black, .white]

    @discardableResult
    static func open(image: CGImage, scale: CGFloat) -> EditorController {
        let e = EditorController(image: image, scale: scale)
        open.append(e)
        e.present()
        return e
    }

    private init(image: CGImage, scale: CGFloat) {
        base = image
        self.scale = scale
        canvas = CanvasView(base: image, scale: scale)
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 360)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        canvas.editor = self
        buildUI()
        updateTitle()
        updateStatus(color: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func present() {
        guard let window, let screen = NSScreen.underMouse.visibleFrame as NSRect? else { return }
        let img = canvas.frame.size
        let chrome = NSSize(width: 0, height: 44 + 36)
        let maxW = screen.width * 0.85, maxH = screen.height * 0.85 - chrome.height
        let pad: CGFloat = 48   // поля вокруг картинки
        let fit = min(1, (maxW - pad) / img.width, (maxH - pad) / img.height)
        let minW = window.minSize.width
        let content = NSSize(width: min(screen.width, max(minW, img.width * fit + pad)),
                             height: max(380, img.height * fit + pad + chrome.height))
        window.setContentSize(content)
        window.setFrameOrigin(NSPoint(x: screen.midX - window.frame.width / 2, y: screen.midY - window.frame.height / 2))
        AppPolicy.windowWillAppear()
        showWindow(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        zoomToFit()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Инструменты
        toolControl.segmentCount = Tool.allCases.count
        toolControl.trackingMode = .selectOne
        for t in Tool.allCases {
            toolControl.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title), forSegment: t.rawValue)
            toolControl.setToolTip(t.title, forSegment: t.rawValue)
            toolControl.setWidth(30, forSegment: t.rawValue)
        }
        toolControl.selectedSegment = tool.rawValue
        toolControl.target = self
        toolControl.action = #selector(toolPicked)

        colorWell.color = .systemRed
        colorWell.toolTip = L("Другой цвет…", "Custom color…")
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 34).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true

        swatchButtons = Self.palette.enumerated().map { i, c in
            let b = NSButton(title: "", target: self, action: #selector(swatchPicked(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.backgroundColor = c.cgColor
            b.layer?.cornerRadius = 9
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 18).isActive = true
            b.heightAnchor.constraint(equalToConstant: 18).isActive = true
            return b
        }
        let swatches = NSStackView(views: swatchButtons)
        swatches.spacing = 5

        // Толщина: четыре точки разного размера.
        widthControl.segmentCount = Self.widths.count
        widthControl.trackingMode = .selectOne
        for (i, w) in Self.widths.enumerated() {
            widthControl.setImage(Self.dot(diameter: 3 + w * 0.9), forSegment: i)
            widthControl.setWidth(26, forSegment: i)
            widthControl.setToolTip([L("Тонко", "Thin"), L("Средне", "Medium"), L("Толсто", "Thick"), L("Очень толсто", "Extra thick")][i], forSegment: i)
        }
        widthControl.selectedSegment = 1
        widthControl.target = self
        widthControl.action = #selector(widthChanged)

        let undoButton = iconButton("arrow.uturn.backward", L("Отменить (⌘Z)", "Undo (⌘Z)"), #selector(undo(_:)))
        let redoButton = iconButton("arrow.uturn.forward", L("Повторить (⇧⌘Z)", "Redo (⇧⌘Z)"), #selector(redo(_:)))

        let top = NSStackView(views: [toolControl, spacer(), swatches, colorWell, widthControl, undoButton, redoButton])
        top.orientation = .horizontal
        top.spacing = 10
        top.setCustomSpacing(6, after: swatches)
        top.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        updateSwatchSelection()

        // Холст
        scrollView.documentView = canvas
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 16
        scrollView.backgroundColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.86, alpha: 1) }
        scrollView.drawsBackground = true

        // Нижняя панель
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor(white: 0.5, alpha: 0.6).cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: 14).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 14).isActive = true
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bottom = NSStackView(views: [
            swatch, statusLabel, spacer(),
            textButton(L("Текст (OCR)", "Text (OCR)"), "text.viewfinder", #selector(recognizeText)),
            textButton(L("Закрепить", "Pin"), "pin", #selector(pin)),
            textButton(L("Копировать", "Copy"), "doc.on.doc", #selector(copy(_:))),
            textButton(L("Сохранить", "Save"), "square.and.arrow.down", #selector(saveDocument(_:))),
        ])
        bottom.orientation = .horizontal
        bottom.spacing = 8
        bottom.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 10)

        let root = NSStackView(views: [top, scrollView, bottom])
        root.orientation = .vertical
        root.spacing = 0
        root.setHuggingPriority(.defaultLow, for: .vertical)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
            top.heightAnchor.constraint(equalToConstant: 44),
            bottom.heightAnchor.constraint(equalToConstant: 36),
        ])
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Окно не уже панели инструментов, иначе она обрежется.
        window?.minSize = NSSize(width: top.fittingSize.width, height: 360)
        canvas.shadow = {
            let sh = NSShadow()
            sh.shadowColor = NSColor(white: 0, alpha: 0.35)
            sh.shadowBlurRadius = 8
            sh.shadowOffset = NSSize(width: 0, height: -2)
            return sh
        }()
    }

    private static func dot(diameter: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: (r.width - diameter) / 2, y: (r.height - diameter) / 2,
                                        width: diameter, height: diameter)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // Выбранный цвет обведён кольцом.
    private func updateSwatchSelection() {
        let current = colorWell.color.usingColorSpace(.sRGB)
        for (i, b) in swatchButtons.enumerated() {
            let c = Self.palette[i].usingColorSpace(.sRGB)
            let same = current != nil && c != nil &&
                abs(current!.redComponent - c!.redComponent) < 0.01 &&
                abs(current!.greenComponent - c!.greenComponent) < 0.01 &&
                abs(current!.blueComponent - c!.blueComponent) < 0.01
            b.layer?.borderWidth = same ? 2.5 : 1
            b.layer?.borderColor = same ? NSColor.controlAccentColor.cgColor : NSColor(white: 0.5, alpha: 0.5).cgColor
        }
    }

    // Показать цвет и толщину выделенной аннотации, не меняя её.
    func showStyle(of a: Annotation) {
        colorWell.color = a.color
        if let i = Self.widths.firstIndex(of: a.width) { widthControl.selectedSegment = i }
        updateSwatchSelection()
    }

    func zoomToFit() {
        let avail = scrollView.contentSize
        let img = canvas.frame.size
        guard img.width > 0, img.height > 0, avail.width > 0 else { return }
        scrollView.magnification = min(1, (avail.width - 40) / img.width, (avail.height - 40) / img.height)
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }

    private func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        return b
    }

    private func textButton(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!,
                         target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        return b
    }

    private func updateTitle() {
        window?.title = "ShotCap — \(base.width) × \(base.height)"
    }

    func updateStatus(color: NSColor?, extra: String? = nil) {
        var parts = ["\(base.width) × \(base.height) px"]
        if let p = canvas.hoverPoint {
            parts.append("x: \(Int(p.x * scale))  y: \(Int(p.y * scale))")
        }
        if let color { parts.append(color.hex) }
        if let extra { parts.append(extra) }
        statusLabel.stringValue = parts.joined(separator: "   ·   ")
        swatch.layer?.backgroundColor = (color ?? .clear).cgColor
        swatch.isHidden = color == nil
    }

    // MARK: Actions

    @objc private func toolPicked() {
        tool = Tool(rawValue: toolControl.selectedSegment) ?? .select
    }

    @objc private func colorChanged() { updateSwatchSelection(); canvas.styleChanged() }
    @objc private func widthChanged() { canvas.styleChanged() }

    @objc private func swatchPicked(_ sender: NSButton) {
        colorWell.color = Self.palette[sender.tag]
        updateSwatchSelection()
        canvas.styleChanged()
    }

    func pickColor(_ c: NSColor) { colorWell.color = c; updateSwatchSelection() }

    func pushUndo() {
        undoStack.append(Snapshot(base: base, annotations: canvas.annotations))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    @objc func undo(_ sender: Any?) {
        canvas.commitText()
        guard let s = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(Snapshot(base: base, annotations: canvas.annotations))
        restore(s)
    }

    @objc func redo(_ sender: Any?) {
        guard let s = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(Snapshot(base: base, annotations: canvas.annotations))
        restore(s)
    }

    private func restore(_ s: Snapshot) {
        base = s.base
        canvas.reset(base: s.base, annotations: s.annotations)
        updateTitle()
        updateStatus(color: nil)
    }

    func applyCrop(_ rect: CGRect) {
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard px.width >= 2, px.height >= 2,
              let cropped = Scene.flatten(base: base, scale: scale, annotations: canvas.annotations).cropping(to: px) else { return }
        pushUndo()
        base = cropped
        canvas.reset(base: cropped, annotations: [])
        updateTitle()
        updateStatus(color: nil)
    }

    var flattened: CGImage {
        canvas.commitText()
        return Scene.flatten(base: base, scale: scale, annotations: canvas.annotations)
    }

    @objc func copy(_ sender: Any?) {
        ImageExport.copy(flattened, scale: scale)
        Toast.show(L("Скопировано в буфер обмена", "Copied to clipboard"))
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let url = ImageExport.save(flattened, scale: scale, to: savedURL) else { return }
        savedURL = url
        Toast.show(L("Сохранено: \(url.lastPathComponent)", "Saved: \(url.lastPathComponent)"), actions: [(L("Показать в Finder", "Show in Finder"), {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        })])
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.directoryURL = Prefs.screenshotFolder
        panel.nameFieldStringValue = ImageExport.fileName(prefix: "Screenshot", ext: Prefs.imageFormat)
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            if let saved = ImageExport.save(self.flattened, scale: self.scale, to: url) { self.savedURL = saved }
        }
    }

    @objc func pin() {
        PinWindow.show(image: flattened, scale: scale)
        close()
    }

    @objc func recognizeText() {
        let image = flattened
        statusLabel.stringValue = L("Распознаю текст…", "Recognizing text…")
        OCR.recognize(image) { [weak self] text in
            guard let self else { return }
            self.updateStatus(color: nil)
            OCRResultPanel.show(text: text, parent: self.window)
        }
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
        AppPolicy.windowDidClose()
    }
}

final class EditorWindow: NSWindow {
    // У приложения нет постоянного главного меню (оно в строке меню), поэтому ловим сочетания здесь.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let editor = windowController as? EditorController,
              !(firstResponder is NSTextView) else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (mods, key) {
        case ([.command], "c"): editor.copy(nil)
        case ([.command], "s"): editor.saveDocument(nil)
        case ([.command, .shift], "s"): editor.saveDocumentAs(nil)
        case ([.command], "z"): editor.undo(nil)
        case ([.command, .shift], "z"): editor.redo(nil)
        case ([.command], "w"): performClose(nil)
        case ([.command], "p"): editor.pin()
        case ([.command], "="), ([.command], "+"): editor.zoom(by: 1.25)
        case ([.command], "-"): editor.zoom(by: 0.8)
        case ([.command], "0"): editor.zoomActual()
        case ([.command], "9"): editor.zoomToFit()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

extension EditorController {
    func zoom(by factor: CGFloat) {
        scrollView.magnification *= factor
    }

    func zoomActual() {
        scrollView.magnification = 1
    }
}

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

// MARK: - Canvas

final class CanvasView: NSView, NSTextFieldDelegate {
    weak var editor: EditorController!
    private var base: CGImage
    private let scale: CGFloat
    private(set) var annotations: [Annotation] = []

    private var draft: Annotation?
    private var selected: Int? { didSet { needsDisplay = true } }
    private var dragLast: CGPoint?
    private var movedSinceDown = false
    private var cropStart: CGPoint?
    private var cropRect: CGRect?
    private var ruler: (CGPoint, CGPoint)?
    private(set) var hoverPoint: CGPoint?

    private var textField: NSTextField?
    private var editingIndex: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset(base: CGImage, annotations: [Annotation]) {
        self.base = base
        self.annotations = annotations
        selected = nil
        draft = nil
        cropRect = nil
        ruler = nil
        setFrameSize(NSSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale))
        needsDisplay = true
    }

    func toolChanged() {
        commitText()
        selected = nil
        cropRect = nil
        ruler = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // Смена цвета/толщины применяется и к выделенной аннотации.
    func styleChanged() {
        guard let i = selected else { return }
        editor.pushUndo()
        annotations[i].color = editor.color
        annotations[i].width = editor.lineWidth
        needsDisplay = true
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch editor?.tool ?? .select {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(visibleRect, cursor: cursor)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let magnified = (enclosingScrollView?.magnification ?? 1) > 1.5
        NSGraphicsContext.current?.imageInterpolation = magnified ? .none : .high
        var all = annotations
        if let draft { all.append(draft) }
        Scene.render(base: base, scale: scale, annotations: all, size: bounds.size, skip: editingIndex)

        if let i = selected, i < annotations.count {
            let p = NSBezierPath(rect: annotations[i].bounds.insetBy(dx: -4, dy: -4))
            p.setLineDash([4, 3], count: 2, phase: 0)
            p.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            p.stroke()
        }

        if let crop = cropRect {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: crop))
            path.windingRule = .evenOdd
            NSColor(white: 0, alpha: 0.5).setFill()
            path.fill()
            NSColor.white.setStroke()
            NSBezierPath(rect: crop).stroke()
            label("\(Int(crop.width * scale)) × \(Int(crop.height * scale))", at: CGPoint(x: crop.minX, y: crop.maxY + 4))
        }

        if let (a, b) = ruler {
            let p = NSBezierPath()
            p.move(to: a); p.line(to: b)
            p.lineWidth = 1.5
            NSColor.systemPink.setStroke()
            p.stroke()
            for pt in [a, b] {
                NSColor.systemPink.setFill()
                NSBezierPath(ovalIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)).fill()
            }
            label(rulerText(a, b), at: CGPoint(x: (a.x + b.x) / 2 + 8, y: (a.y + b.y) / 2 + 8))
        }
    }

    private func rulerText(_ a: CGPoint, _ b: CGPoint) -> String {
        let dx = abs(b.x - a.x) * scale, dy = abs(b.y - a.y) * scale
        return "\(Int(hypot(dx, dy).rounded())) px  (Δx \(Int(dx.rounded())), Δy \(Int(dy.rounded())))"
    }

    private func label(_ text: String, at p: CGPoint) {
        let mag = enclosingScrollView?.magnification ?? 1
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11 / mag, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let r = CGRect(x: p.x, y: p.y, width: size.width + 10 / mag, height: size.height + 4 / mag)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: r, xRadius: 4 / mag, yRadius: 4 / mag).fill()
        (text as NSString).draw(at: CGPoint(x: r.minX + 5 / mag, y: r.minY + 2 / mag), withAttributes: attrs)
    }

    // MARK: Mouse

    private func point(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func hit(_ p: CGPoint) -> Int? {
        annotations.indices.reversed().first { annotations[$0].hitTest(p) }
    }

    // С Shift: квадрат/круг или угол, кратный 45°.
    private func constrained(_ a: CGPoint, _ b: CGPoint, kind: Annotation.Kind, shift: Bool) -> CGPoint {
        guard shift else { return b }
        let dx = b.x - a.x, dy = b.y - a.y
        switch kind {
        case .rect, .ellipse, .pixelate, .spotlight:
            let s = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + (dx < 0 ? -s : s), y: a.y + (dy < 0 ? -s : s))
        case .arrow, .line:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: a.x + cos(angle) * len, y: a.y + sin(angle) * len)
        default:
            return b
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        if textField != nil { commitText(); if editor.tool == .text { return } }
        movedSinceDown = false
        dragLast = p

        switch editor.tool {
        case .select:
            selected = hit(p)
            if let i = selected { editor.showStyle(of: annotations[i]) }
            if event.clickCount == 2, let i = selected, annotations[i].kind == .text { beginText(at: annotations[i].start, editing: i) }
        case .text:
            if let i = hit(p), annotations[i].kind == .text {
                beginText(at: annotations[i].start, editing: i)
            } else {
                beginText(at: CGPoint(x: p.x, y: p.y - editorFont.pointSize * 0.6), editing: nil)
            }
        case .counter:
            editor.pushUndo()
            let n = (annotations.filter { $0.kind == .counter }.map(\.number).max() ?? 0) + 1
            annotations.append(Annotation(kind: .counter, points: [p], color: editor.color, width: editor.lineWidth, number: n))
        case .crop:
            cropStart = p
            cropRect = nil
        case .eyedropper:
            if let c = color(at: p) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(c.hex, forType: .string)
                editor.pickColor(c)
                Toast.show(L("Цвет \(c.hex) скопирован", "Color \(c.hex) copied"))
            }
        case .ruler:
            ruler = (p, p)
        default:
            if let kind = editor.tool.annotationKind {
                draft = Annotation(kind: kind, points: [p, p], color: editor.color, width: editor.lineWidth)
                if kind == .pen || kind == .marker { draft?.points = [p] }
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        hoverPoint = p
        let shift = event.modifierFlags.contains(.shift)
        switch editor.tool {
        case .select:
            guard let i = selected, let last = dragLast else { break }
            if !movedSinceDown { editor.pushUndo(); movedSinceDown = true }
            annotations[i].move(dx: p.x - last.x, dy: p.y - last.y)
            dragLast = p
        case .crop:
            if let s = cropStart { cropRect = Annotation.rect(s, constrained(s, p, kind: .rect, shift: shift)).intersection(bounds) }
        case .ruler:
            if let r = ruler { ruler = (r.0, constrained(r.0, p, kind: .line, shift: shift)) }
            editor.updateStatus(color: nil, extra: ruler.map { rulerText($0.0, $0.1) })
        default:
            guard var d = draft else { break }
            if d.kind == .pen || d.kind == .marker {
                if let last = d.points.last, hypot(last.x - p.x, last.y - p.y) > 1 { d.points.append(p) }
            } else {
                d.points[1] = constrained(d.start, p, kind: d.kind, shift: shift)
            }
            draft = d
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let d = draft {
            if d.isSignificant {
                editor.pushUndo()
                annotations.append(d)
            }
            draft = nil
        }
        if editor.tool == .crop, let r = cropRect {
            cropRect = nil
            cropStart = nil
            if r.width > 3, r.height > 3 { editor.applyCrop(r) }
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        hoverPoint = p
        editor.updateStatus(color: color(at: p))
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        editor.updateStatus(color: nil)
    }

    private func color(at p: CGPoint) -> NSColor? {
        ImageExport.pixelColor(base, x: Int(p.x * scale), y: Int(p.y * scale))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        switch event.keyCode {
        case 51, 117: // ⌫ ⌦
            if let i = selected {
                editor.pushUndo()
                annotations.remove(at: i)
                selected = nil
            }
        case 53: // Esc
            if selected != nil || ruler != nil || cropRect != nil {
                selected = nil; ruler = nil; cropRect = nil
                needsDisplay = true
            } else {
                window?.performClose(nil)
            }
        case 123, 124, 125, 126: // стрелки двигают выделенное
            guard let i = selected else { break }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let d: (CGFloat, CGFloat) = [123: (-step, 0), 124: (step, 0), 125: (0, step), 126: (0, -step)][event.keyCode]!
            editor.pushUndo()
            annotations[i].move(dx: d.0, dy: d.1)
            needsDisplay = true
        default:
            if mods.isEmpty, let ch = event.charactersIgnoringModifiers?.lowercased().first,
               let t = Tool.allCases.first(where: { $0.key == ch }) {
                editor.tool = t
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Text

    private var editorFont: NSFont {
        Annotation(kind: .text, points: [.zero], color: .black, width: editor.lineWidth).font
    }

    private func beginText(at p: CGPoint, editing index: Int?) {
        commitText()
        let existing = index.map { annotations[$0] }
        let font = existing?.font ?? editorFont
        let field = NSTextField(string: existing?.text ?? "")
        field.font = font
        field.textColor = existing?.color ?? editor.color
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor(white: 0.5, alpha: 0.25)
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.placeholderString = L("Текст", "Text")
        field.frame = CGRect(origin: p, size: CGSize(width: 40, height: font.pointSize * 1.3))
        addSubview(field)
        textField = field
        editingIndex = index
        resizeField()
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    private func resizeField() {
        guard let f = textField else { return }
        let size = NSAttributedString(string: f.stringValue.isEmpty ? L("Текст", "Text") : f.stringValue,
                                      attributes: [.font: f.font!]).size()
        f.setFrameSize(NSSize(width: size.width + 16, height: size.height + 2))
    }

    func controlTextDidChange(_ obj: Notification) { resizeField() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        let origin = field.frame.origin
        let color = field.textColor ?? editor.color
        field.delegate = nil
        field.removeFromSuperview()
        if let i = editingIndex {
            editor.pushUndo()
            if text.isEmpty { annotations.remove(at: i) } else { annotations[i].text = text }
        } else if !text.isEmpty {
            editor.pushUndo()
            annotations.append(Annotation(kind: .text, points: [origin], color: color, width: editor.lineWidth, text: text))
        }
        editingIndex = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}
