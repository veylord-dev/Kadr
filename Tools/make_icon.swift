// Рисует иконку приложения: swift Tools/make_icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Фон: тёмный скруглённый квадрат по сетке macOS (824pt с отступом 100).
    let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.06, alpha: 1))!.draw(in: bg, angle: -90)

    // Мелкие размеры — толще линии, иначе они теряются.
    let small = px <= 64
    let line: CGFloat = small ? 52 : 34

    // Тонкие уголки видоискателя.
    let p = NSBezierPath()
    let a: CGFloat = 300, b: CGFloat = 724, l: CGFloat = 112
    p.move(to: NSPoint(x: a, y: a + l)); p.line(to: NSPoint(x: a, y: a)); p.line(to: NSPoint(x: a + l, y: a))
    p.move(to: NSPoint(x: b - l, y: a)); p.line(to: NSPoint(x: b, y: a)); p.line(to: NSPoint(x: b, y: a + l))
    p.move(to: NSPoint(x: b, y: b - l)); p.line(to: NSPoint(x: b, y: b)); p.line(to: NSPoint(x: b - l, y: b))
    p.move(to: NSPoint(x: a + l, y: b)); p.line(to: NSPoint(x: a, y: b)); p.line(to: NSPoint(x: a, y: b - l))
    p.lineWidth = line
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    NSColor(white: 0.96, alpha: 1).setStroke()
    p.stroke()

    // Точка записи.
    let r: CGFloat = small ? 78 : 64
    NSColor(calibratedRed: 1, green: 0.27, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 - r, y: 512 - r, width: r * 2, height: r * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
