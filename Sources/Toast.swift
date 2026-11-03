import AppKit

// Ненавязчивое уведомление в правом нижнем углу (без прав на уведомления).
final class Toast: NSPanel {
    private static var current: Toast?
    private var actions: [() -> Void] = []
    private var timer: Timer?

    static func show(_ text: String, image: CGImage? = nil, scale: CGFloat = 2,
                     actions: [(String, () -> Void)] = [], duration: TimeInterval? = nil) {
        current?.close()
        let t = Toast(text: text, image: image, scale: scale, actions: actions)
        current = t
        t.orderFrontRegardless()
        t.timer = Timer.scheduledTimer(withTimeInterval: duration ?? (actions.isEmpty ? 2.5 : 6), repeats: false) { [weak t] _ in
            t?.fadeOut()
        }
    }

    private init(text: String, image: CGImage?, scale: CGFloat, actions: [(String, () -> Void)]) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.actions = actions.map(\.1)

        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.state = .active
        fx.blendingMode = .behindWindow
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 12
        fx.layer?.masksToBounds = true

        let inner: CGFloat = 292   // ширина содержимого: картинка, текст и кнопки не вылезают за край
        var views: [NSView] = []
        if let image {
            let iv = NSImageView(image: ImageExport.nsImage(image, scale: scale))
            iv.imageScaling = .scaleProportionallyDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 6
            iv.translatesAutoresizingMaskIntoConstraints = false
            let aspect = CGFloat(image.height) / max(1, CGFloat(image.width))
            iv.widthAnchor.constraint(equalToConstant: inner).isActive = true
            iv.heightAnchor.constraint(equalToConstant: min(170, inner * aspect)).isActive = true
            views.append(iv)
        }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = inner
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: inner).isActive = true
        views.append(label)
        if !actions.isEmpty {
            let buttons = NSStackView(views: actions.enumerated().map { i, a in
                let b = NSButton(title: a.0, target: nil, action: nil)
                b.tag = i
                b.target = self
                b.action = #selector(tapped(_:))
                b.bezelStyle = .rounded
                b.controlSize = .small
                return b
            })
            buttons.spacing = 6
            buttons.distribution = .fillEqually
            buttons.translatesAutoresizingMaskIntoConstraints = false
            buttons.widthAnchor.constraint(equalToConstant: inner).isActive = true
            views.append(buttons)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor),
            stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        contentView = fx
        let size = fx.fittingSize
        let screen = NSScreen.underMouse.visibleFrame
        setFrame(NSRect(x: screen.maxX - size.width - 20, y: screen.minY + 20, width: size.width, height: size.height), display: true)
    }

    @objc private func tapped(_ sender: NSButton) {
        let action = actions[sender.tag]
        close()
        action()
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.close() })
    }

    override func close() {
        timer?.invalidate()
        super.close()
        if Toast.current === self { Toast.current = nil }
    }
}

// MARK: - Countdown before recording

final class Countdown: NSPanel {
    private static var current: Countdown?
    private let label = NSTextField(labelWithString: "")

    static func run(_ seconds: Int, in rect: NSRect, done: @escaping () -> Void) {
        guard seconds > 0 else { done(); return }
        let c = Countdown(center: NSPoint(x: rect.midX, y: rect.midY))
        current = c
        c.orderFrontRegardless()
        var left = seconds
        c.label.stringValue = "\(left)"
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            left -= 1
            if left <= 0 {
                t.invalidate()
                c.close()
                current = nil
                // Даём окну отсчёта исчезнуть из кадра.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: done)
            } else {
                c.label.stringValue = "\(left)"
            }
        }
    }

    private init(center: NSPoint) {
        let side: CGFloat = 140
        super.init(contentRect: NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        bg.layer?.cornerRadius = side / 2
        label.font = .systemFont(ofSize: 72, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (side - 90) / 2, width: side, height: 90)
        bg.addSubview(label)
        contentView = bg
    }
}
