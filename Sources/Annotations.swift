import AppKit

enum Tool: Int, CaseIterable {
    case select, arrow, line, rect, ellipse, pen, marker, text, counter, pixelate, spotlight, crop, eyedropper, ruler

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "scribble"
        case .marker: return "highlighter"
        case .text: return "textformat"
        case .counter: return "1.circle"
        case .pixelate: return "square.grid.3x3.fill"
        case .spotlight: return "flashlight.on.fill"
        case .crop: return "crop"
        case .eyedropper: return "eyedropper"
        case .ruler: return "ruler"
        }
    }

    var title: String {
        switch self {
        case .select: return L("Выбор и перемещение (V)", "Select and move (V)")
        case .arrow: return L("Стрелка (A)", "Arrow (A)")
        case .line: return L("Линия (L)", "Line (L)")
        case .rect: return L("Прямоугольник (R)", "Rectangle (R)")
        case .ellipse: return L("Овал (O)", "Oval (O)")
        case .pen: return L("Карандаш (P)", "Pen (P)")
        case .marker: return L("Маркер (M)", "Highlighter (M)")
        case .text: return L("Текст (T)", "Text (T)")
        case .counter: return L("Нумерация шагов (N)", "Step counter (N)")
        case .pixelate: return L("Размытие / пикселизация (B)", "Blur / pixelate (B)")
        case .spotlight: return L("Прожектор: затемнить всё, кроме области (S)", "Spotlight: dim everything except an area (S)")
        case .crop: return L("Обрезка (K)", "Crop (K)")
        case .eyedropper: return L("Пипетка — клик копирует HEX (I)", "Color picker — click copies HEX (I)")
        case .ruler: return L("Линейка в пикселях (U)", "Pixel ruler (U)")
        }
    }

    var key: Character {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .line: return "l"
        case .rect: return "r"
        case .ellipse: return "o"
        case .pen: return "p"
        case .marker: return "m"
        case .text: return "t"
        case .counter: return "n"
        case .pixelate: return "b"
        case .spotlight: return "s"
        case .crop: return "k"
        case .eyedropper: return "i"
        case .ruler: return "u"
        }
    }

    var annotationKind: Annotation.Kind? {
        switch self {
        case .arrow: return .arrow
        case .line: return .line
        case .rect: return .rect
        case .ellipse: return .ellipse
        case .pen: return .pen
        case .marker: return .marker
        case .pixelate: return .pixelate
        case .spotlight: return .spotlight
        default: return nil
        }
    }
}

// Аннотация — значение, поэтому снимок массива сразу годится для отмены.
struct Annotation {
    enum Kind { case arrow, line, rect, ellipse, pen, marker, text, counter, pixelate, spotlight }

    var kind: Kind
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var number = 0

    var start: CGPoint { points[0] }
    var end: CGPoint { points[points.count - 1] }
    var font: NSFont { .systemFont(ofSize: 14 + width * 2.5, weight: .bold) }
    var counterDiameter: CGFloat { 20 + width * 2.5 }

    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var attributedText: NSAttributedString {
        NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: font, .foregroundColor: color])
    }

    var bounds: CGRect {
        switch kind {
        case .text:
            return CGRect(origin: start, size: attributedText.size())
        case .counter:
            let d = counterDiameter
            return CGRect(x: start.x - d / 2, y: start.y - d / 2, width: d, height: d)
        case .pen, .marker:
            let xs = points.map(\.x), ys = points.map(\.y)
            let pad = kind == .marker ? width * 2.5 : width
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                .insetBy(dx: -pad, dy: -pad)
        case .arrow:
            return Annotation.rect(start, end).insetBy(dx: -arrowHead, dy: -arrowHead)
        default:
            return Annotation.rect(start, end).insetBy(dx: -width, dy: -width)
        }
    }

    var isSignificant: Bool {
        switch kind {
        case .pen, .marker: return points.count > 1
        case .arrow, .line: return hypot(end.x - start.x, end.y - start.y) > 4
        default: return Annotation.rect(start, end).width > 3 && Annotation.rect(start, end).height > 3
        }
    }

    private var arrowHead: CGFloat { max(14, width * 4.5) }

    func hitTest(_ p: CGPoint) -> Bool {
        switch kind {
        case .arrow, .line:
            return distance(p, start, end) < max(8, width + 4)
        case .pen, .marker:
            return zip(points, points.dropFirst()).contains { distance(p, $0, $1) < max(8, width * 2) }
        case .rect, .ellipse:
            let r = Annotation.rect(start, end)
            return r.insetBy(dx: -6, dy: -6).contains(p) && !r.insetBy(dx: 8, dy: 8).contains(p)
        default:
            return bounds.insetBy(dx: -4, dy: -4).contains(p)
        }
    }

    private func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    mutating func move(dx: CGFloat, dy: CGFloat) {
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    // MARK: Drawing (в текущем перевёрнутом NSGraphicsContext, координаты в пунктах)

    func draw(base: CGImage, scale: CGFloat, canvas: CGSize) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        switch kind {
        case .arrow:
            shadow.set()
            color.setFill()
            arrowPath().fill()
        case .line:
            shadow.set()
            color.setStroke()
            let p = NSBezierPath()
            p.move(to: start); p.line(to: end)
            p.lineWidth = width
            p.lineCapStyle = .round
            p.stroke()
        case .rect:
            shadow.set()
            color.setStroke()
            let p = NSBezierPath(roundedRect: Annotation.rect(start, end), xRadius: 3, yRadius: 3)
            p.lineWidth = width
            p.stroke()
        case .ellipse:
            shadow.set()
            color.setStroke()
            let p = NSBezierPath(ovalIn: Annotation.rect(start, end))
            p.lineWidth = width
            p.stroke()
        case .pen:
            shadow.set()
            color.setStroke()
            let p = smoothPath()
            p.lineWidth = width
            p.stroke()
        case .marker:
            ctx.compositingOperation = .multiply
            color.withAlphaComponent(0.45).setStroke()
            let p = smoothPath()
            p.lineWidth = width * 5
            p.lineCapStyle = .square
            p.stroke()
        case .text:
            shadow.set()
            attributedText.draw(at: start)
        case .counter:
            shadow.set()
            let r = bounds
            color.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSShadow().set()
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 2
            ring.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: counterDiameter * 0.55, weight: .heavy),
                .foregroundColor: color.isLight ? NSColor.black : NSColor.white,
            ]
            let s = "\(number)" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        case .pixelate:
            drawPixelated(base: base, scale: scale)
        case .spotlight:
            // Рисуется общим слоем в Scene (несколько прожекторов объединяются).
            break
        }
    }

    private func arrowPath() -> NSBezierPath {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = max(hypot(dx, dy), 0.001)
        let ux = dx / len, uy = dy / len, nx = -uy, ny = ux
        let head = min(arrowHead, len * 0.6)
        let shaftEnd = CGPoint(x: end.x - ux * head * 0.8, y: end.y - uy * head * 0.8)
        let tail = width * 0.35, neck = width * 0.6
        let p = NSBezierPath()
        p.move(to: CGPoint(x: start.x + nx * tail, y: start.y + ny * tail))
        p.line(to: CGPoint(x: shaftEnd.x + nx * neck, y: shaftEnd.y + ny * neck))
        p.line(to: CGPoint(x: end.x - ux * head + nx * head * 0.55, y: end.y - uy * head + ny * head * 0.55))
        p.line(to: end)
        p.line(to: CGPoint(x: end.x - ux * head - nx * head * 0.55, y: end.y - uy * head - ny * head * 0.55))
        p.line(to: CGPoint(x: shaftEnd.x - nx * neck, y: shaftEnd.y - ny * neck))
        p.line(to: CGPoint(x: start.x - nx * tail, y: start.y - ny * tail))
        p.close()
        p.lineJoinStyle = .round
        return p
    }

    private func smoothPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        guard points.count > 1 else { return p }
        p.move(to: points[0])
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            p.curve(to: mid, controlPoint1: points[i - 1], controlPoint2: points[i - 1])
        }
        p.line(to: end)
        return p
    }

    private func drawPixelated(base: CGImage, scale: CGFloat) {
        let r = Annotation.rect(start, end)
        let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !px.isEmpty, let crop = base.cropping(to: px) else { return }
        let block = max(4, Int(9 * scale))
        let w = max(1, crop.width / block), h = max(1, crop.height / block)
        guard let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let tiny = small.makeImage() else { return }
        let dst = CGRect(x: px.minX / scale, y: px.minY / scale, width: px.width / scale, height: px.height / scale)
        NSImage(cgImage: tiny, size: dst.size).draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1,
                                                    respectFlipped: true,
                                                    hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
    }
}

extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.7
    }
}

// MARK: - Scene rendering

enum Scene {
    static func render(base: CGImage, scale: CGFloat, annotations: [Annotation], size: CGSize, skip: Int? = nil) {
        let bounds = CGRect(origin: .zero, size: size)
        NSImage(cgImage: base, size: size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                                                respectFlipped: true, hints: nil)
        // Сначала размытие — чтобы стрелки поверх оставались чёткими.
        for (i, a) in annotations.enumerated() where a.kind == .pixelate && i != skip {
            a.draw(base: base, scale: scale, canvas: size)
        }
        let spots = annotations.filter { $0.kind == .spotlight }
        if !spots.isEmpty {
            let path = NSBezierPath(rect: bounds)
            for s in spots {
                path.append(NSBezierPath(roundedRect: Annotation.rect(s.start, s.end), xRadius: 6, yRadius: 6))
            }
            path.windingRule = .evenOdd
            NSColor(white: 0, alpha: 0.55).setFill()
            path.fill()
        }
        for (i, a) in annotations.enumerated() where a.kind != .pixelate && i != skip {
            a.draw(base: base, scale: scale, canvas: size)
        }
    }

    // Итоговое изображение в полном разрешении.
    static func flatten(base: CGImage, scale: CGFloat, annotations: [Annotation]) -> CGImage {
        guard !annotations.isEmpty else { return base }
        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        ctx.translateBy(x: 0, y: CGFloat(base.height))
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        render(base: base, scale: scale, annotations: annotations,
               size: CGSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? base
    }
}
