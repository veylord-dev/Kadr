import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Geometry

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static var underMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }
}

enum Geometry {
    // Высота главного экрана: CG-координаты отсчитываются от его левого верхнего угла.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    // CG (верх-лево) <-> Cocoa (низ-лево); формула симметрична.
    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

// MARK: - Windows on screen

struct WindowInfo {
    let id: CGWindowID
    let frame: NSRect       // Cocoa-координаты
    let pid: pid_t
    let owner: String
    let title: String
}

enum WindowList {
    // Окна в порядке спереди назад — для попадания курсором.
    static func onScreen() -> [WindowInfo] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 40, bounds.height > 40,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return WindowInfo(id: id, frame: Geometry.flip(bounds), pid: pid,
                              owner: info[kCGWindowOwnerName as String] as? String ?? "",
                              title: info[kCGWindowName as String] as? String ?? "")
        }
    }
}

// MARK: - ScreenCaptureKit

struct CaptureError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum Capture {
    static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = L("Нужен доступ к записи экрана", "Screen recording access required")
        alert.informativeText = L("Разрешите Kadr в «Системные настройки → Конфиденциальность и безопасность → Запись экрана и системного аудио», затем перезапустите приложение.", "Allow Kadr in “System Settings → Privacy & Security → Screen & System Audio Recording”, then restart the app.")
        alert.addButton(withTitle: L("Открыть настройки", "Open Settings"))
        alert.addButton(withTitle: L("Позже", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openPrivacySettings() }
        return false
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    // Снимок каждого экрана в полном разрешении — «замороженный» экран для выделения.
    static func captureDisplays() async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await content()
        var result: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            cfg.width = Int(filter.contentRect.width * scale)
            cfg.height = Int(filter.contentRect.height * scale)
            cfg.showsCursor = false
            cfg.captureResolution = .best
            result[display.displayID] = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        }
        return result
    }

    // Окно отдельно от остального рабочего стола (с прозрачными скруглёнными углами).
    static func captureWindow(_ id: CGWindowID) async throws -> (CGImage, CGFloat) {
        let content = try await content()
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError(L("Окно не найдено", "Window not found"))
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int(filter.contentRect.width * scale)
        cfg.height = Int(filter.contentRect.height * scale)
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        cfg.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return (image, scale)
    }

    static func playShutter() {
        guard Prefs.sound else { return }
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        (NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink"))?.play()
    }
}

// MARK: - Image helpers

enum ImageExport {
    static func data(_ image: CGImage, scale: CGFloat, format: String) -> Data? {
        let type = (format == "jpg" ? UTType.jpeg : UTType.png).identifier as CFString
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        // DPI = 72 × масштаб, чтобы Retina-снимок открывался в «родном» размере.
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
        if format == "jpg" { props[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    static func nsImage(_ image: CGImage, scale: CGFloat) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
    }

    static func copy(_ image: CGImage, scale: CGFloat) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        pb.declareTypes([.png, .tiff], owner: nil)
        if let png = data(image, scale: scale, format: "png") { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    static func fileName(prefix: String, ext: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(f.string(from: Date())).\(ext)"
    }

    @discardableResult
    static func save(_ image: CGImage, scale: CGFloat, to url: URL? = nil) -> URL? {
        let format = url.map { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" ? "jpg" : "png" }
            ?? Prefs.imageFormat
        let target = url ?? Prefs.screenshotFolder.appendingPathComponent(fileName(prefix: "Screenshot", ext: format))
        guard let d = data(image, scale: scale, format: format), (try? d.write(to: target)) != nil else {
            Toast.show(L("Не удалось сохранить файл", "Could not save the file"))
            return nil
        }
        return target
    }

    // Изображение из NSImage (буфер обмена, файл) с масштабом по его представлению.
    static func cgImage(from image: NSImage) -> (CGImage, CGFloat)? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let rep = image.representations.first
        let scale = rep.map { $0.size.width > 0 ? CGFloat($0.pixelsWide) / $0.size.width : 1 } ?? 1
        return (cg, max(1, scale.rounded()))
    }

    static func pixelColor(_ image: CGImage, x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(srgbRed: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255,
                       blue: CGFloat(bytes[2]) / 255, alpha: 1)
    }
}

extension NSColor {
    var hex: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
