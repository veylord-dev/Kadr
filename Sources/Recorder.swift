import AppKit
import AVFoundation
import ScreenCaptureKit

enum RecordTarget {
    case display(NSScreen)
    case area(NSScreen, NSRect)     // Cocoa-координаты
    case window(CGWindowID)
    case app(pid_t)
}

// Запись экрана через ScreenCaptureKit (SCRecordingOutput сам пишет файл с видео и звуком).
final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    static let shared = Recorder()

    enum State { case idle, starting, recording, stopping }
    private(set) var state: State = .idle { didSet { onStateChange?() } }
    var isBusy: Bool { state != .idle }
    private(set) var startDate: Date?
    var onStateChange: (() -> Void)?

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var fileURL: URL?
    private var frame: RecordingFrame?
    private var hud: RecordingHUD?

    // MARK: Start

    func start(_ target: RecordTarget) {
        guard state == .idle else { return }
        state = .starting
        Task { @MainActor in
            do {
                if Prefs.microphone { _ = await AVCaptureDevice.requestAccess(for: .audio) }
                let (filter, cfg, area) = try await self.makeFilter(target)
                Countdown.run(Prefs.countdown, in: area) {
                    Task { @MainActor in
                        do { try await self.begin(filter: filter, cfg: cfg, target: target, area: area) } catch { self.fail(error) }
                    }
                }
            } catch {
                self.fail(error)
            }
        }
    }

    private func makeFilter(_ target: RecordTarget) async throws -> (SCContentFilter, SCStreamConfiguration, NSRect) {
        let content = try await Capture.content()
        let me = content.applications.filter { $0.processID == getpid() }
        let cfg = SCStreamConfiguration()
        let filter: SCContentFilter
        var area: NSRect

        func display(for screen: NSScreen) throws -> SCDisplay {
            guard let d = content.displays.first(where: { $0.displayID == screen.displayID }) else {
                throw CaptureError(L("Экран не найден", "Display not found"))
            }
            return d
        }

        switch target {
        case .display(let screen):
            filter = SCContentFilter(display: try display(for: screen), excludingApplications: me, exceptingWindows: [])
            let s = CGFloat(filter.pointPixelScale)
            cfg.width = even(filter.contentRect.width * s)
            cfg.height = even(filter.contentRect.height * s)
            area = screen.frame

        case .area(let screen, let rect):
            filter = SCContentFilter(display: try display(for: screen), excludingApplications: me, exceptingWindows: [])
            let s = CGFloat(filter.pointPixelScale)
            // sourceRect — в пунктах относительно левого верхнего угла экрана.
            cfg.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                    width: rect.width, height: rect.height)
            cfg.width = even(rect.width * s)
            cfg.height = even(rect.height * s)
            area = rect

        case .window(let id):
            guard let w = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError(L("Окно не найдено", "Window not found")) }
            filter = SCContentFilter(desktopIndependentWindow: w)
            let s = CGFloat(filter.pointPixelScale)
            cfg.width = even(filter.contentRect.width * s)
            cfg.height = even(filter.contentRect.height * s)
            cfg.ignoreShadowsSingleWindow = true
            area = Geometry.flip(w.frame)

        case .app(let pid):
            guard let app = content.applications.first(where: { $0.processID == pid }) else {
                throw CaptureError(L("Приложение не найдено", "App not found"))
            }
            // Экран, на котором у приложения больше всего окон.
            let wins = content.windows.filter { $0.owningApplication?.processID == pid && $0.isOnScreen && $0.windowLayer == 0 }
            let d = content.displays.max { a, b in
                coverage(a.frame, wins) < coverage(b.frame, wins)
            } ?? content.displays[0]
            filter = SCContentFilter(display: d, including: [app], exceptingWindows: [])
            let s = CGFloat(filter.pointPixelScale)
            cfg.width = even(filter.contentRect.width * s)
            cfg.height = even(filter.contentRect.height * s)
            area = Geometry.flip(d.frame)
        }

        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Prefs.fps))
        cfg.showsCursor = Prefs.showCursor
        cfg.showMouseClicks = Prefs.showClicks
        cfg.captureResolution = .best
        cfg.queueDepth = 8
        cfg.capturesAudio = Prefs.systemAudio
        cfg.excludesCurrentProcessAudio = true
        cfg.captureMicrophone = Prefs.microphone
        return (filter, cfg, area)
    }

    private func coverage(_ displayFrame: CGRect, _ windows: [SCWindow]) -> CGFloat {
        windows.reduce(0) { acc, w in
            let i = w.frame.intersection(displayFrame)
            return acc + (i.isNull ? 0 : i.width * i.height)
        }
    }

    private func even(_ v: CGFloat) -> Int { max(2, Int(v.rounded()) & ~1) }

    @MainActor
    private func begin(filter: SCContentFilter, cfg: SCStreamConfiguration, target: RecordTarget, area: NSRect) async throws {
        let ext = Prefs.videoFormat
        let url = Prefs.videoFolder.appendingPathComponent(ImageExport.fileName(prefix: "Recording", ext: ext))
        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = url
        rc.outputFileType = ext == "mov" ? .mov : .mp4
        rc.videoCodecType = Prefs.videoCodec == "hevc" ? .hevc : .h264

        let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
        let output = SCRecordingOutput(configuration: rc, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        self.fileURL = url
        self.startDate = Date()
        state = .recording

        if case .area(_, let rect) = target { frame = RecordingFrame(rect: rect) }
        hud = RecordingHUD(near: area)
    }

    // MARK: Stop

    func stop() {
        guard state == .recording, let stream else { return }
        state = .stopping
        Task { @MainActor in
            do { try await stream.stopCapture() } catch { NSLog("stopCapture: \(error)") }
            // Файл дописывается в recordingOutputDidFinishRecording; страховка, если колбэк не придёт.
            self.finishLater()
        }
    }

    private func cleanup() {
        frame?.close(); frame = nil
        hud?.close(); hud = nil
        stream = nil
        output = nil
        startDate = nil
        state = .idle
    }

    private func fail(_ error: Error) {
        cleanup()
        NSLog("Recording failed: \(error)")
        Toast.show(L("Не удалось записать: \(error.localizedDescription)", "Recording failed: \(error.localizedDescription)"))
    }

    private func finishLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.state == .stopping { self.finished() }
        }
    }

    private func finished() {
        let url = fileURL
        cleanup()
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        Toast.show(L("Запись сохранена: \(url.lastPathComponent)", "Recording saved: \(url.lastPathComponent)"), actions: [
            (L("Открыть", "Open"), { NSWorkspace.shared.open(url) }),
            (L("Показать в Finder", "Show in Finder"), { NSWorkspace.shared.activateFileViewerSelecting([url]) }),
            (L("Копировать файл", "Copy file"), {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }),
        ], duration: 10)
    }

    // MARK: Delegates

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Например, пользователь остановил запись из системного индикатора.
        DispatchQueue.main.async {
            if self.state == .recording { self.state = .stopping }
            self.finishLater()
        }
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async { self.fail(error) }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { self.finished() }
    }
}

// MARK: - Frame around recorded area (не попадает в запись: окна приложения исключены)

final class RecordingFrame: NSWindow {
    init(rect: NSRect) {
        let r = rect.insetBy(dx: -4, dy: -4)
        super.init(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = FrameView(frame: NSRect(origin: .zero, size: r.size))
        orderFrontRegardless()
    }

    private final class FrameView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let p = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            p.lineWidth = 2
            p.setLineDash([8, 5], count: 2, phase: 0)
            NSColor.systemRed.setStroke()
            p.stroke()
        }
    }
}

// MARK: - HUD with timer and Stop button

final class RecordingHUD: NSPanel {
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private var timer: Timer?

    init(near area: NSRect) {
        let size = NSSize(width: 150, height: 36)
        let screen = NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.underMouse
        var origin = NSPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 12)
        if origin.y < screen.visibleFrame.minY + 8 { origin.y = screen.visibleFrame.maxY - size.height - 8 }
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        super.init(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = size.height / 2
        fx.layer?.masksToBounds = true

        let dot = NSImageView(image: NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)!)
        dot.contentTintColor = .systemRed
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let stop = NSButton(title: L("Стоп", "Stop"), target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded
        stop.controlSize = .small
        let stack = NSStackView(views: [dot, timeLabel, stop])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        stack.frame = fx.bounds
        stack.autoresizingMask = [.width, .height]
        fx.addSubview(stack)
        contentView = fx
        orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard let start = Recorder.shared.startDate else { return }
        timeLabel.stringValue = RecordingHUD.format(Date().timeIntervalSince(start))
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    @objc private func stopTapped() { Recorder.shared.stop() }

    override func close() {
        timer?.invalidate()
        super.close()
    }
}
