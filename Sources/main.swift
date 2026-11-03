import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum ShotPurpose { case normal, ocr, pin }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let appsMenu = NSMenu()
    private var actionItems: [HotAction: NSMenuItem] = [:]
    private var tickTimer: Timer?
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        enableLaunchAtLoginOnFirstRun()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        buildMenu()
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            self?.menu.removeAllItems()
            self?.actionItems.removeAll()
            self?.buildMenu()
            NSApp.mainMenu = buildMainMenu()
        }
        updateStatusIcon()

        HotKeyCenter.shared.handler = { [weak self] in self?.perform($0) }
        HotKeyCenter.shared.registerAll()
        NotificationCenter.default.addObserver(forName: .hotkeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshShortcuts()
        }
        Recorder.shared.onStateChange = { [weak self] in self?.updateStatusIcon() }

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        func add(_ action: HotAction, _ symbol: String) {
            let item = NSMenuItem(title: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = self
            actionItems[action] = item
            menu.addItem(item)
        }
        func item(_ title: String, _ symbol: String?, _ sel: Selector, key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.target = self
            if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            return i
        }

        menu.addItem(header(L("Скриншот", "Screenshot")))
        add(.captureArea, "rectangle.dashed")
        add(.captureWindow, "macwindow")
        add(.captureScreen, "display")
        let delayed = NSMenuItem(title: L("С задержкой", "Delayed"), action: nil, keyEquivalent: "")
        delayed.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let delayedMenu = NSMenu()
        for s in [3, 5, 10] {
            let i = item(L("\(s) секунд", "\(s) seconds"), nil, #selector(delayedCapture(_:)))
            i.tag = s
            delayedMenu.addItem(i)
        }
        delayed.submenu = delayedMenu
        menu.addItem(delayed)
        add(.captureOCR, "text.viewfinder")
        add(.capturePin, "pin")
        menu.addItem(item(L("Редактировать из буфера обмена", "Edit from clipboard"), "doc.on.clipboard", #selector(editClipboard)))
        menu.addItem(item(L("Открыть изображение…", "Open image…"), "photo", #selector(openImage)))

        menu.addItem(.separator())
        menu.addItem(header(L("Запись видео", "Recording")))
        add(.recordArea, "rectangle.dashed.badge.record")
        add(.recordWindow, "macwindow.badge.plus")
        let apps = NSMenuItem(title: L("Запись приложения", "Record app"), action: nil, keyEquivalent: "")
        apps.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        apps.submenu = appsMenu
        appsMenu.delegate = self
        menu.addItem(apps)
        add(.recordScreen, "record.circle")

        menu.addItem(.separator())
        menu.addItem(item(L("Папка скриншотов", "Screenshots folder"), "folder", #selector(openShotsFolder)))
        menu.addItem(item(L("Папка записей", "Recordings folder"), "film", #selector(openVideoFolder)))
        loginItem = item(L("Запускать при входе в систему", "Launch at login"), nil, #selector(toggleLaunchAtLogin))
        menu.addItem(loginItem)
        menu.addItem(item(L("Настройки…", "Settings…"), "gearshape", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("Выйти из Kadr", "Quit Kadr"), nil, #selector(quit), key: "q"))
        refreshShortcuts()
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func refreshShortcuts() {
        for (action, item) in actionItems {
            if let s = action.shortcut, !s.menuKey.isEmpty {
                item.keyEquivalent = s.menuKey
                item.keyEquivalentModifierMask = s.modifiers
            } else {
                item.keyEquivalent = ""
            }
        }
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        if m === menu { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off }
        guard m === appsMenu else { return }
        m.removeAllItems()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in apps {
            let i = NSMenuItem(title: app.localizedName ?? "?", action: #selector(recordApp(_:)), keyEquivalent: "")
            i.target = self
            i.tag = Int(app.processIdentifier)
            if let icon = app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                i.image = icon
            }
            m.addItem(i)
        }
        if apps.isEmpty { m.addItem(withTitle: L("Нет запущенных приложений", "No running apps"), action: nil, keyEquivalent: "") }
    }

    // Во время записи клик по значку сразу останавливает её.
    @objc private func statusClicked() {
        if Recorder.shared.state == .recording {
            Recorder.shared.stop()
        } else {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        }
    }

    func menuDidClose(_ m: NSMenu) {
        if m === menu { statusItem.menu = nil }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        tickTimer?.invalidate()
        if Recorder.shared.state == .recording {
            let img = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: L("Остановить запись", "Stop recording"))!
                .withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))
            button.image = img
            button.imagePosition = .imageLeading
            let tick = { [weak button] in
                guard let start = Recorder.shared.startDate else { return }
                button?.title = " " + RecordingHUD.format(Date().timeIntervalSince(start))
            }
            tick()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
        } else {
            button.title = ""
            button.image = Self.icon()
        }
    }

    private static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Тонкие уголки видоискателя + точка записи — тот же мотив, что в иконке приложения.
            let p = NSBezierPath()
            let a: CGFloat = 3, b: CGFloat = 15, l: CGFloat = 3.6
            p.move(to: NSPoint(x: a, y: a + l)); p.line(to: NSPoint(x: a, y: a)); p.line(to: NSPoint(x: a + l, y: a))
            p.move(to: NSPoint(x: b - l, y: a)); p.line(to: NSPoint(x: b, y: a)); p.line(to: NSPoint(x: b, y: a + l))
            p.move(to: NSPoint(x: b, y: b - l)); p.line(to: NSPoint(x: b, y: b)); p.line(to: NSPoint(x: b - l, y: b))
            p.move(to: NSPoint(x: a + l, y: b)); p.line(to: NSPoint(x: a, y: b)); p.line(to: NSPoint(x: a, y: b - l))
            p.lineWidth = 1.4
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            NSColor.black.setStroke()
            p.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 7.2, width: 3.6, height: 3.6)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kadr"
        return image
    }

    // MARK: Actions

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotAction(rawValue: raw) else { return }
        // Меню должно закрыться и не попасть в снимок.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.perform(action) }
    }

    private func perform(_ action: HotAction) {
        guard !SelectionOverlay.isActive else { return }
        switch action {
        case .captureArea: screenshot(windowMode: false, purpose: .normal)
        case .captureWindow: screenshot(windowMode: true, purpose: .normal)
        case .captureScreen: fullScreenshot()
        case .captureOCR: screenshot(windowMode: false, purpose: .ocr)
        case .capturePin: screenshot(windowMode: false, purpose: .pin)
        case .recordArea: record(windowMode: false)
        case .recordWindow: record(windowMode: true)
        case .recordScreen:
            if toggleStop() { return }
            guard Capture.ensurePermission() else { return }
            Recorder.shared.start(.display(NSScreen.underMouse))
        }
    }

    @objc private func delayedCapture(_ sender: NSMenuItem) {
        let seconds = sender.tag
        Toast.show(L("Снимок через \(seconds) с — откройте нужное меню или окно", "Capturing in \(seconds) s — open the menu or window you need"), duration: 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            self.screenshot(windowMode: false, purpose: .normal)
        }
    }

    // MARK: Screenshots

    private func screenshot(windowMode: Bool, purpose: ShotPurpose) {
        guard Capture.ensurePermission() else { return }
        Task { @MainActor in
            do {
                let frozen = try await Capture.captureDisplays()
                SelectionOverlay.begin(purpose: .screenshot, windowMode: windowMode, frozen: frozen) { result in
                    self.handle(result, frozen: frozen, purpose: purpose)
                }
            } catch {
                Toast.show(L("Не удалось снять экран: \(error.localizedDescription)", "Screen capture failed: \(error.localizedDescription)"))
            }
        }
    }

    private func fullScreenshot() {
        guard Capture.ensurePermission() else { return }
        let screen = NSScreen.underMouse
        Task { @MainActor in
            do {
                let frozen = try await Capture.captureDisplays()
                self.handle(.fullScreen(screen), frozen: frozen, purpose: .normal)
            } catch {
                Toast.show(L("Не удалось снять экран: \(error.localizedDescription)", "Screen capture failed: \(error.localizedDescription)"))
            }
        }
    }

    private func handle(_ result: SelectionResult?, frozen: [CGDirectDisplayID: CGImage], purpose: ShotPurpose) {
        guard let result else { return }
        switch result {
        case .area(let screen, let rect):
            guard let img = frozen[screen.displayID] else { return }
            let scale = CGFloat(img.width) / screen.frame.width
            let crop = CGRect(x: (rect.minX - screen.frame.minX) * scale, y: (screen.frame.maxY - rect.maxY) * scale,
                              width: rect.width * scale, height: rect.height * scale).integral
            guard let cut = img.cropping(to: crop) else { return }
            deliver(cut, scale: scale, purpose: purpose)
        case .fullScreen(let screen):
            guard let img = frozen[screen.displayID] else { return }
            deliver(img, scale: CGFloat(img.width) / screen.frame.width, purpose: purpose)
        case .window(let info):
            Task { @MainActor in
                do {
                    let (img, scale) = try await Capture.captureWindow(info.id)
                    self.deliver(img, scale: scale, purpose: purpose)
                } catch {
                    Toast.show(L("Не удалось снять окно: \(error.localizedDescription)", "Window capture failed: \(error.localizedDescription)"))
                }
            }
        case .app:
            break
        }
    }

    private func deliver(_ image: CGImage, scale: CGFloat, purpose: ShotPurpose) {
        Capture.playShutter()
        switch purpose {
        case .ocr:
            OCR.recognize(image) { text in
                if text.isEmpty {
                    Toast.show(L("Текст не найден", "No text found"))
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    Toast.show(L("Текст скопирован:\n", "Text copied:\n") + String(text.prefix(160)) + (text.count > 160 ? "…" : ""),
                               actions: [(L("Показать весь", "Show all"), { OCRResultPanel.show(text: text, parent: nil) })])
                }
            }
            return
        case .pin:
            PinWindow.show(image: image, scale: scale)
            return
        case .normal:
            break
        }

        if Prefs.copyOnCapture { ImageExport.copy(image, scale: scale) }
        switch Prefs.afterCapture {
        case .editor:
            EditorController.open(image: image, scale: scale)
        case .clipboard:
            if !Prefs.copyOnCapture { ImageExport.copy(image, scale: scale) }
            Toast.show(L("Скопировано в буфер обмена", "Copied to clipboard"), image: image, scale: scale, actions: [
                (L("Редактировать", "Edit"), { EditorController.open(image: image, scale: scale) }),
                (L("Сохранить", "Save"), { ImageExport.save(image, scale: scale) }),
                (L("Закрепить", "Pin"), { PinWindow.show(image: image, scale: scale) }),
            ])
        case .save:
            if let url = ImageExport.save(image, scale: scale) {
                Toast.show(L("Сохранено: \(url.lastPathComponent)", "Saved: \(url.lastPathComponent)"), image: image, scale: scale, actions: [
                    (L("Редактировать", "Edit"), { EditorController.open(image: image, scale: scale) }),
                    (L("Показать в Finder", "Show in Finder"), { NSWorkspace.shared.activateFileViewerSelecting([url]) }),
                ])
            }
        case .pin:
            PinWindow.show(image: image, scale: scale)
        }
    }

    @objc private func editClipboard() {
        guard let ns = NSImage(pasteboard: .general), let (img, scale) = ImageExport.cgImage(from: ns) else {
            Toast.show(L("В буфере обмена нет изображения", "No image on the clipboard"))
            return
        }
        EditorController.open(image: img, scale: scale)
    }

    @objc private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let ns = NSImage(contentsOf: url),
              let (img, scale) = ImageExport.cgImage(from: ns) else { return }
        EditorController.open(image: img, scale: scale)
    }

    // MARK: Recording

    private func toggleStop() -> Bool {
        switch Recorder.shared.state {
        case .recording: Recorder.shared.stop(); return true
        case .idle: return false
        default: return true
        }
    }

    private func record(windowMode: Bool) {
        if toggleStop() { return }
        guard Capture.ensurePermission() else { return }
        SelectionOverlay.begin(purpose: .record, windowMode: windowMode, frozen: [:]) { result in
            guard let result else { return }
            switch result {
            case .area(let s, let r): Recorder.shared.start(.area(s, r))
            case .window(let w): Recorder.shared.start(.window(w.id))
            case .app(let pid): Recorder.shared.start(.app(pid))
            case .fullScreen(let s): Recorder.shared.start(.display(s))
            }
        }
    }

    @objc private func recordApp(_ sender: NSMenuItem) {
        if toggleStop() { return }
        guard Capture.ensurePermission() else { return }
        let pid = pid_t(sender.tag)
        NSRunningApplication(processIdentifier: pid)?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Recorder.shared.start(.app(pid)) }
    }

    // MARK: Launch at login

    // Автозапуск включается сам при первом запуске; дальше — как выберет пользователь.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "launchAtLoginConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setLaunchAtLogin(true)
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(SMAppService.mainApp.status != .enabled)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Login item: \(error)")
            if on { Toast.show(L("Не удалось включить автозапуск: \(error.localizedDescription)", "Could not enable launch at login: \(error.localizedDescription)")) }
        }
        SystemState.shared.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Misc

    @objc private func openShotsFolder() { NSWorkspace.shared.open(Prefs.screenshotFolder) }
    @objc private func openVideoFolder() { NSWorkspace.shared.open(Prefs.videoFolder) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }

    @objc private func quit() {
        if Recorder.shared.state == .recording {
            Recorder.shared.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
        } else {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindowController.shared.show() }
        return true
    }
}

// Главное меню нужно, чтобы в полях ввода работали ⌘C/⌘V/⌘A, пока приложение в Dock.
private func buildMainMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: L("Настройки…", "Settings…"), action: Selector(("openSettingsFromMenu:")), keyEquivalent: ",")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: L("Скрыть Kadr", "Hide Kadr"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: L("Выйти из Kadr", "Quit Kadr"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    main.addItem(appItem)

    let editItem = NSMenuItem()
    let edit = NSMenu(title: L("Правка", "Edit"))
    edit.addItem(withTitle: L("Отменить", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: L("Повторить", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: L("Вырезать", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: L("Копировать", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: L("Вставить", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: L("Выбрать все", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)

    let windowItem = NSMenuItem()
    let window = NSMenu(title: L("Окно", "Window"))
    window.addItem(withTitle: L("Закрыть", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    window.addItem(withTitle: L("Свернуть", "Minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
    windowItem.submenu = window
    main.addItem(windowItem)
    return main
}

extension NSApplication {
    @objc func openSettingsFromMenu(_ sender: Any?) { SettingsWindowController.shared.show() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = buildMainMenu()
app.setActivationPolicy(.accessory)
app.run()
