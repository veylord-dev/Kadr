import AppKit
import Carbon.HIToolbox

enum SelectionPurpose { case screenshot, record }

enum SelectionResult {
    case area(NSScreen, NSRect)     // Cocoa-координаты
    case window(WindowInfo)
    case app(pid_t)
    case fullScreen(NSScreen)
}

// Полноэкранное выделение области/окна поверх всех экранов.
// Для скриншота экран «замораживается»: под курсором — лупа с пикселями и цветом.
final class SelectionOverlay {
    private static var current: SelectionOverlay?
    static var isActive: Bool { current != nil }

    enum Drag {
        case none, create(NSPoint), move(NSPoint, NSRect), resize(Int, NSRect)
    }

    let purpose: SelectionPurpose
    var windowMode: Bool
    let frozen: [CGDirectDisplayID: CGImage]
    let windowList: [WindowInfo]
    private var windows: [OverlayWindow] = []
    private let completion: (SelectionResult?) -> Void

    var mouse = NSEvent.mouseLocation
    var selection: NSRect?
    var selectionScreen: NSScreen?
    var adjusting = false           // запись: рамку можно подвинуть перед стартом
    var drag: Drag = .none
    var hovered: WindowInfo?

    static func begin(purpose: SelectionPurpose, windowMode: Bool, frozen: [CGDirectDisplayID: CGImage],
                      completion: @escaping (SelectionResult?) -> Void) {
        guard current == nil else { return }
        current = SelectionOverlay(purpose: purpose, windowMode: windowMode, frozen: frozen, completion: completion)
    }

    private init(purpose: SelectionPurpose, windowMode: Bool, frozen: [CGDirectDisplayID: CGImage],
                 completion: @escaping (SelectionResult?) -> Void) {
        self.purpose = purpose
        self.windowMode = windowMode
        self.frozen = frozen
        self.windowList = WindowList.onScreen()
        self.completion = completion

        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen, controller: self, image: frozen[screen.displayID])
            windows.append(w)
            w.orderFrontRegardless()
        }
        updateHover()
        (windows.first { $0.screenRef == NSScreen.underMouse } ?? windows.first)?.makeKey()
        NSCursor.crosshair.set()
    }

    func finish(_ result: SelectionResult?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        Self.current = nil
        NSCursor.arrow.set()
        // Даём окнам исчезнуть до того, как кто-то начнёт захват.
        DispatchQueue.main.async { self.completion(result) }
    }

    func redraw() {
        windows.forEach { $0.contentView?.needsDisplay = true }
    }

    func screen(at p: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    func updateHover() {
        hovered = windowList.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: Handles

    static func handlePoints(_ r: NSRect) -> [NSPoint] {
        [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.midX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
         NSPoint(x: r.maxX, y: r.midY), NSPoint(x: r.maxX, y: r.maxY), NSPoint(x: r.midX, y: r.maxY),
         NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.minX, y: r.midY)]
    }

    private func handle(at p: NSPoint, _ r: NSRect) -> Int? {
        Self.handlePoints(r).firstIndex { hypot($0.x - p.x, $0.y - p.y) < 9 }
    }

    private func clamp(_ r: NSRect) -> NSRect {
        guard let s = selectionScreen else { return r }
        return r.intersection(s.frame).integral
    }

    // MARK: Mouse

    func mouseMoved() {
        mouse = NSEvent.mouseLocation
        updateHover()
        redraw()
    }

    func mouseDown() {
        mouse = NSEvent.mouseLocation
        if adjusting, let sel = selection {
            if let h = handle(at: mouse, sel) {
                drag = .resize(h, sel)
            } else if NSMouseInRect(mouse, sel, false) {
                drag = .move(mouse, sel)
            } else {
                adjusting = false
                setControlsVisible(false)
                startCreate()
            }
            return
        }
        if windowMode { drag = .none; return }
        startCreate()
    }

    private func startCreate() {
        drag = .create(mouse)
        selectionScreen = screen(at: mouse)
        selection = nil
    }

    func mouseDragged() {
        mouse = NSEvent.mouseLocation
        switch drag {
        case .none:
            break
        case .create(let start):
            let r = NSRect(x: min(start.x, mouse.x), y: min(start.y, mouse.y),
                           width: abs(mouse.x - start.x), height: abs(mouse.y - start.y))
            selection = clamp(r)
        case .move(let start, let orig):
            guard let s = selectionScreen else { break }
            var r = orig.offsetBy(dx: mouse.x - start.x, dy: mouse.y - start.y)
            r.origin.x = min(max(r.minX, s.frame.minX), s.frame.maxX - r.width)
            r.origin.y = min(max(r.minY, s.frame.minY), s.frame.maxY - r.height)
            selection = r.integral
        case .resize(let h, let orig):
            var minX = orig.minX, maxX = orig.maxX, minY = orig.minY, maxY = orig.maxY
            if [0, 6, 7].contains(h) { minX = mouse.x }
            if [2, 3, 4].contains(h) { maxX = mouse.x }
            if [0, 1, 2].contains(h) { minY = mouse.y }
            if [4, 5, 6].contains(h) { maxY = mouse.y }
            selection = clamp(NSRect(x: min(minX, maxX), y: min(minY, maxY),
                                     width: abs(maxX - minX), height: abs(maxY - minY)))
        }
        updateHover()
        layoutControls()
        redraw()
    }

    func mouseUp(modifiers: NSEvent.ModifierFlags) {
        mouse = NSEvent.mouseLocation
        let wasCreating: Bool
        if case .create = drag { wasCreating = true } else { wasCreating = false }
        drag = .none

        let tiny = (selection.map { $0.width < 4 || $0.height < 4 } ?? true)
        if windowMode || (wasCreating && tiny) {
            // Клик без перетаскивания — окно под курсором.
            if let w = hovered {
                finish(purpose == .record && modifiers.contains(.option) ? .app(w.pid) : .window(w))
            } else if let s = screen(at: mouse) {
                finish(.fullScreen(s))
            }
            return
        }
        guard let sel = selection, let s = selectionScreen else { return }
        if purpose == .screenshot {
            if wasCreating { finish(.area(s, sel)) }
        } else {
            adjusting = true
            setControlsVisible(true)
            layoutControls()
        }
        redraw()
    }

    // MARK: Keyboard

    func keyDown(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            finish(nil)
        case kVK_Space:
            guard !adjusting else { return }
            windowMode.toggle()
            selection = nil
            redraw()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if adjusting { confirm() } else { finish(.fullScreen(screen(at: mouse) ?? NSScreen.underMouse)) }
        case kVK_ANSI_C:
            copyColorUnderCursor()
        default:
            break
        }
    }

    func confirm() {
        guard let sel = selection, let s = selectionScreen else { return }
        finish(.area(s, sel))
    }

    func colorUnderCursor() -> NSColor? {
        guard let s = screen(at: mouse), let img = frozen[s.displayID] else { return nil }
        let scale = CGFloat(img.width) / s.frame.width
        let x = Int((mouse.x - s.frame.minX) * scale)
        let y = Int((s.frame.maxY - mouse.y) * scale)
        return ImageExport.pixelColor(img, x: min(x, img.width - 1), y: min(y, img.height - 1))
    }

    private func copyColorUnderCursor() {
        guard let c = colorUnderCursor() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(c.hex, forType: .string)
        finish(nil)
        Toast.show(L("Цвет \(c.hex) скопирован", "Color \(c.hex) copied"))
    }

    // MARK: Record controls

    private func setControlsVisible(_ visible: Bool) {
        for w in windows {
            (w.contentView as? OverlayView)?.controls.isHidden = !(visible && w.screenRef == selectionScreen)
        }
    }

    private func layoutControls() {
        guard adjusting else { return }
        windows.forEach { ($0.contentView as? OverlayView)?.layoutControls() }
    }
}

// MARK: - Window

final class OverlayWindow: NSWindow {
    let screenRef: NSScreen

    init(screen: NSScreen, controller: SelectionOverlay, image: CGImage?) {
        screenRef = screen
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = OverlayView(screen: screen, controller: controller, image: image)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

final class OverlayView: NSView {
    private let screen: NSScreen
    private unowned let ctl: SelectionOverlay
    private let image: CGImage?
    private let nsImage: NSImage?
    let controls = NSStackView()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(screen: NSScreen, controller: SelectionOverlay, image: CGImage?) {
        self.screen = screen
        self.ctl = controller
        self.image = image
        self.nsImage = image.map { NSImage(cgImage: $0, size: screen.frame.size) }
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        buildControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Глобальные Cocoa-координаты -> локальные (верх-лево).
    private func local(_ p: NSPoint) -> NSPoint {
        NSPoint(x: p.x - screen.frame.minX, y: screen.frame.maxY - p.y)
    }

    private func local(_ r: NSRect) -> NSRect {
        NSRect(x: r.minX - screen.frame.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height)
    }

    private var pixelScale: CGFloat {
        image.map { CGFloat($0.width) / screen.frame.width } ?? screen.backingScaleFactor
    }

    // MARK: Events

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set(); ctl.mouseMoved() }
    override func mouseDown(with event: NSEvent) { ctl.mouseDown() }
    override func mouseDragged(with event: NSEvent) { ctl.mouseDragged() }
    override func mouseUp(with event: NSEvent) { ctl.mouseUp(modifiers: event.modifierFlags) }
    override func rightMouseDown(with event: NSEvent) { ctl.finish(nil) }
    override func keyDown(with event: NSEvent) { ctl.keyDown(event) }

    // MARK: Record controls

    private func buildControls() {
        let start = NSButton(title: L("Начать запись", "Start recording"), target: self, action: #selector(startTapped))
        start.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)
        start.imagePosition = .imageLeading
        start.contentTintColor = .systemRed
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        let cancel = NSButton(title: L("Отмена", "Cancel"), target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        controls.layer?.cornerRadius = 10
        controls.addArrangedSubview(start)
        controls.addArrangedSubview(cancel)
        controls.isHidden = true
        addSubview(controls)
    }

    func layoutControls() {
        guard let sel = ctl.selection, ctl.selectionScreen == screen else { return }
        let r = local(sel)
        let size = controls.fittingSize
        var origin = NSPoint(x: r.midX - size.width / 2, y: r.maxY + 10)
        if origin.y + size.height > bounds.height - 10 { origin.y = r.maxY - size.height - 10 }
        origin.x = min(max(10, origin.x), bounds.width - size.width - 10)
        controls.frame = NSRect(origin: origin, size: size)
    }

    @objc private func startTapped() { ctl.confirm() }
    @objc private func cancelTapped() { ctl.finish(nil) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let nsImage {
            nsImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }

        let mouseHere = NSMouseInRect(ctl.mouse, screen.frame, false)
        var hole: NSRect?
        var dim: CGFloat = 0

        if let sel = ctl.selection, ctl.selectionScreen == screen, !ctl.windowMode {
            hole = local(sel)
            dim = 0.45
        } else if ctl.selection != nil && !ctl.windowMode {
            dim = 0.45
        } else if ctl.windowMode {
            dim = 0.4
            if let w = ctl.hovered { hole = local(w.frame) }
        }

        if dim > 0 {
            let path = NSBezierPath(rect: bounds)
            if let hole { path.append(NSBezierPath(rect: hole)); path.windingRule = .evenOdd }
            NSColor(white: 0, alpha: dim).setFill()
            path.fill()
        }

        if ctl.windowMode, let w = ctl.hovered {
            drawWindowHighlight(local(w.frame), title: w.owner, strong: true)
        } else if ctl.selection == nil, mouseHere, let w = ctl.hovered {
            // Подсказка: клик без перетаскивания снимет это окно.
            let r = local(w.frame)
            NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
            let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
            p.lineWidth = 2
            p.stroke()
        }

        if let hole, ctl.selection != nil, !ctl.windowMode {
            drawSelection(hole)
        }

        let creating: Bool
        if case .create = ctl.drag { creating = true } else { creating = false }
        if mouseHere, !ctl.windowMode, !ctl.adjusting, ctl.selection == nil || creating {
            drawCrosshair(local(ctl.mouse))
        }
        if mouseHere, image != nil, !ctl.adjusting {
            drawLoupe(at: local(ctl.mouse))
        }
        if mouseHere { drawHint() }
    }

    private func drawSelection(_ r: NSRect) {
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        if ctl.purpose == .record {
            let dash = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            dash.setLineDash([5, 5], count: 2, phase: 0)
            NSColor.systemRed.setStroke()
            dash.stroke()
        }
        if ctl.adjusting {
            for p in SelectionOverlay.handlePoints(r) {
                let h = NSBezierPath(ovalIn: NSRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
                NSColor.white.setFill()
                h.fill()
                NSColor.systemBlue.setStroke()
                h.lineWidth = 1.5
                h.stroke()
            }
        }
        let text = "\(Int(r.width * pixelScale)) × \(Int(r.height * pixelScale))"
        var labelOrigin = NSPoint(x: r.minX, y: r.maxY + 6)
        if labelOrigin.y > bounds.height - 28 { labelOrigin.y = r.maxY - 28 }
        drawLabel(text, at: labelOrigin)
    }

    private func drawWindowHighlight(_ r: NSRect, title: String, strong: Bool) {
        NSColor.systemBlue.withAlphaComponent(0.18).setFill()
        NSBezierPath(rect: r).fill()
        NSColor.systemBlue.setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5))
        p.lineWidth = 3
        p.stroke()
        let size = "\(Int(r.width * pixelScale)) × \(Int(r.height * pixelScale))"
        drawLabel(title.isEmpty ? size : "\(title) · \(size)", at: NSPoint(x: r.minX + 8, y: r.minY + 8))
    }

    private func drawCrosshair(_ p: NSPoint) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor(white: 0, alpha: 0.35).cgColor)
        ctx.strokeLineSegments(between: [CGPoint(x: 0, y: p.y + 1), CGPoint(x: bounds.width, y: p.y + 1),
                                         CGPoint(x: p.x + 1, y: 0), CGPoint(x: p.x + 1, y: bounds.height)])
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.7).cgColor)
        ctx.strokeLineSegments(between: [CGPoint(x: 0, y: p.y + 0.5), CGPoint(x: bounds.width, y: p.y + 0.5),
                                         CGPoint(x: p.x + 0.5, y: 0), CGPoint(x: p.x + 0.5, y: bounds.height)])
        ctx.restoreGState()
    }

    private func drawLoupe(at p: NSPoint) {
        guard let image else { return }
        let cells = 15, cell: CGFloat = 8
        let side = CGFloat(cells) * cell
        var origin = NSPoint(x: p.x + 24, y: p.y + 24)
        if origin.x + side > bounds.width - 8 { origin.x = p.x - 24 - side }
        if origin.y + side + 26 > bounds.height - 8 { origin.y = p.y - 24 - side - 26 }
        let box = NSRect(origin: origin, size: NSSize(width: side, height: side))

        let px = Int(p.x * pixelScale), py = Int(p.y * pixelScale)
        let want = CGRect(x: px - cells / 2, y: py - cells / 2, width: cells, height: cells)
        let avail = want.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        NSColor.black.setFill()
        clip.fill()
        clip.addClip()
        if !avail.isEmpty, let crop = image.cropping(to: avail) {
            let dst = NSRect(x: box.minX + (avail.minX - want.minX) * cell, y: box.minY + (avail.minY - want.minY) * cell,
                             width: avail.width * cell, height: avail.height * cell)
            NSImage(cgImage: crop, size: dst.size)
                .draw(in: dst, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                      hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        }
        NSColor(white: 0.5, alpha: 0.25).setStroke()
        let grid = NSBezierPath()
        for i in 1..<cells {
            let o = CGFloat(i) * cell
            grid.move(to: NSPoint(x: box.minX + o, y: box.minY)); grid.line(to: NSPoint(x: box.minX + o, y: box.maxY))
            grid.move(to: NSPoint(x: box.minX, y: box.minY + o)); grid.line(to: NSPoint(x: box.maxX, y: box.minY + o))
        }
        grid.lineWidth = 0.5
        grid.stroke()
        let center = NSRect(x: box.minX + CGFloat(cells / 2) * cell, y: box.minY + CGFloat(cells / 2) * cell,
                            width: cell, height: cell)
        NSColor.white.setStroke()
        NSBezierPath(rect: center).stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.8).setStroke()
        let frame = NSBezierPath(roundedRect: box.insetBy(dx: -0.5, dy: -0.5), xRadius: 8, yRadius: 8)
        frame.lineWidth = 1
        frame.stroke()

        let hex = ctl.colorUnderCursor()?.hex ?? ""
        drawLabel("\(hex)  \(px), \(py)", at: NSPoint(x: box.minX, y: box.maxY + 4), width: side)
    }

    private func drawHint() {
        let text: String
        if ctl.adjusting {
            text = L("Подвиньте рамку или потяните за углы · ↩ — начать запись · Esc — отмена", "Move the frame or drag its handles · ↩ — start recording · Esc — cancel")
        } else if ctl.windowMode {
            text = ctl.purpose == .record
                ? L("Клик — записать окно · ⌥ + клик — всё приложение · Space — область · Esc — отмена", "Click — record window · ⌥ + click — whole app · Space — area · Esc — cancel")
                : L("Клик — снять окно · Space — выделение области · Esc — отмена", "Click — capture window · Space — select area · Esc — cancel")
        } else {
            text = ctl.purpose == .record
                ? L("Выделите область · клик — окно · Space — режим окон · ↩ — весь экран · Esc — отмена", "Drag to select · click — window · Space — window mode · ↩ — full screen · Esc — cancel")
                : L("Выделите область · клик — окно · Space — режим окон · ↩ — весь экран · C — копировать цвет · Esc — отмена", "Drag to select · click — window · Space — window mode · ↩ — full screen · C — copy color · Esc — cancel")
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let r = NSRect(x: (bounds.width - size.width) / 2 - 12, y: bounds.height - size.height - 40,
                       width: size.width + 24, height: size.height + 12)
        NSColor(white: 0.08, alpha: 0.8).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        (text as NSString).draw(at: NSPoint(x: r.minX + 12, y: r.minY + 6), withAttributes: attrs)
    }

    private func drawLabel(_ text: String, at p: NSPoint, width: CGFloat? = nil) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let r = NSRect(x: p.x, y: p.y, width: width ?? size.width + 12, height: size.height + 6)
        NSColor(white: 0.08, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: r.minX + (r.width - size.width) / 2, y: r.minY + 3), withAttributes: attrs)
    }
}
