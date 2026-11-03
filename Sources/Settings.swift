import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Preferences

enum AfterCapture: String, CaseIterable {
    case editor, clipboard, save, pin

    var title: String {
        switch self {
        case .editor: return L("Открыть редактор", "Open editor")
        case .clipboard: return L("Только скопировать", "Copy only")
        case .save: return L("Сохранить в папку", "Save to folder")
        case .pin: return L("Закрепить поверх окон", "Pin on top")
        }
    }
}

enum Prefs {
    enum Key {
        static let afterCapture = "afterCapture"
        static let copyOnCapture = "copyOnCapture"
        static let imageFormat = "imageFormat"
        static let sound = "sound"
        static let screenshotFolder = "screenshotFolder"
        static let videoFolder = "videoFolder"
        static let fps = "fps"
        static let showCursor = "showCursor"
        static let showClicks = "showClicks"
        static let systemAudio = "systemAudio"
        static let microphone = "microphone"
        static let countdown = "countdown"
        static let videoFormat = "videoFormat"
        static let videoCodec = "videoCodec"
    }

    static func registerDefaults() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        UserDefaults.standard.register(defaults: [
            Key.afterCapture: AfterCapture.editor.rawValue,
            Key.copyOnCapture: true,
            Key.imageFormat: "png",
            Key.sound: true,
            Key.screenshotFolder: pictures.appendingPathComponent("Kadr").path,
            Key.videoFolder: movies.appendingPathComponent("Kadr").path,
            Key.fps: 60,
            Key.showCursor: true,
            Key.showClicks: true,
            Key.systemAudio: false,
            Key.microphone: false,
            Key.countdown: 0,
            Key.videoFormat: "mp4",
            Key.videoCodec: "h264",
        ])
    }

    private static var d: UserDefaults { .standard }
    static var afterCapture: AfterCapture { AfterCapture(rawValue: d.string(forKey: Key.afterCapture) ?? "") ?? .editor }
    static var copyOnCapture: Bool { d.bool(forKey: Key.copyOnCapture) }
    static var imageFormat: String { d.string(forKey: Key.imageFormat) ?? "png" }
    static var sound: Bool { d.bool(forKey: Key.sound) }
    static var fps: Int { max(1, d.integer(forKey: Key.fps)) }
    static var showCursor: Bool { d.bool(forKey: Key.showCursor) }
    static var showClicks: Bool { d.bool(forKey: Key.showClicks) }
    static var systemAudio: Bool { d.bool(forKey: Key.systemAudio) }
    static var microphone: Bool { d.bool(forKey: Key.microphone) }
    static var countdown: Int { d.integer(forKey: Key.countdown) }
    static var videoFormat: String { d.string(forKey: Key.videoFormat) ?? "mp4" }
    static var videoCodec: String { d.string(forKey: Key.videoCodec) ?? "h264" }

    static var screenshotFolder: URL { folder(Key.screenshotFolder) }
    static var videoFolder: URL { folder(Key.videoFolder) }

    private static func folder(_ key: String) -> URL {
        let url = URL(fileURLWithPath: (d.string(forKey: key) ?? NSHomeDirectory()) as NSString as String)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Settings window

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        // Стандартные настройки macOS: вкладки-иконки в панели инструментов.
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false
        for page in SettingsView.Page.allCases {
            let host = NSHostingController(rootView: SettingsView(page: page))
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.title = L("Настройки Kadr", "Kadr Settings")
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateTexts()
        }
    }

    // Подписи вкладок и заголовок — на текущем языке (содержимое SwiftUI обновляется само).
    private func updateTexts() {
        window?.title = L("Настройки Kadr", "Kadr Settings")
        guard let tabs = window?.contentViewController as? NSTabViewController else { return }
        for (item, page) in zip(tabs.tabViewItems, SettingsView.Page.allCases) {
            item.label = page.title
        }
    }

    func windowWillClose(_ notification: Notification) {
        AppPolicy.windowDidClose()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        AppPolicy.windowWillAppear()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ShortcutField: NSViewRepresentable {
    let action: HotAction
    func makeNSView(context: Context) -> ShortcutButton { ShortcutButton(action: action) }
    func updateNSView(_ nsView: ShortcutButton, context: Context) {}
}

private struct FolderRow: View {
    let title: String
    let key: String
    @AppStorage private var path: String

    init(title: String, key: String) {
        self.title = title
        self.key = key
        _path = AppStorage(wrappedValue: "", key)
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button(L("Изменить…", "Change…")) { choose() }
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } label: { Image(systemName: "folder") }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: path)
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

final class SystemState: ObservableObject {
    static let shared = SystemState()
    @Published var hasPermission = CGPreflightScreenCaptureAccess()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { NSLog("Login item: \(error)") }
        }
    }

    func refresh() {
        hasPermission = CGPreflightScreenCaptureAccess()
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
    }
}

struct SettingsView: View {
    enum Page: CaseIterable {
        case general, recording, hotkeys

        var title: String {
            switch self {
            case .general: return L("Основные", "General")
            case .recording: return L("Запись видео", "Recording")
            case .hotkeys: return L("Горячие клавиши", "Shortcuts")
            }
        }

        var height: CGFloat {
            switch self {
            case .general: return 480
            case .recording: return 480
            case .hotkeys: return 440
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .recording: return "record.circle"
            case .hotkeys: return "keyboard"
            }
        }
    }

    let page: Page
    @AppStorage(Prefs.Key.afterCapture) private var afterCapture = AfterCapture.editor.rawValue
    @AppStorage(Prefs.Key.copyOnCapture) private var copyOnCapture = true
    @AppStorage(Prefs.Key.imageFormat) private var imageFormat = "png"
    @AppStorage(Prefs.Key.sound) private var sound = true
    @AppStorage(Prefs.Key.fps) private var fps = 60
    @AppStorage(Prefs.Key.showCursor) private var showCursor = true
    @AppStorage(Prefs.Key.showClicks) private var showClicks = true
    @AppStorage(Prefs.Key.systemAudio) private var systemAudio = false
    @AppStorage(Prefs.Key.microphone) private var microphone = false
    @AppStorage(Prefs.Key.countdown) private var countdown = 0
    @AppStorage(Prefs.Key.videoFormat) private var videoFormat = "mp4"
    @AppStorage(Prefs.Key.videoCodec) private var videoCodec = "h264"
    @ObservedObject private var system = SystemState.shared
    @AppStorage(Language.key) private var language = Language.system.rawValue

    var body: some View {
        Group {
            switch page {
            case .general: general
            case .recording: recording
            case .hotkeys: hotkeys
            }
        }
        .frame(width: 540, height: page.height)
    }

    private var general: some View {
        Form {
            Section(L("После снимка", "After capture")) {
                Picker(L("Действие", "Action"), selection: $afterCapture) {
                    ForEach(AfterCapture.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Toggle(L("Всегда копировать в буфер обмена", "Always copy to clipboard"), isOn: $copyOnCapture)
                Toggle(L("Звук затвора", "Shutter sound"), isOn: $sound)
                Picker(L("Формат файла", "File format"), selection: $imageFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpg")
                }
                FolderRow(title: L("Папка скриншотов", "Screenshots folder"), key: Prefs.Key.screenshotFolder)
            }
            Section(L("Язык", "Language")) {
                Picker(L("Язык интерфейса", "Interface language"), selection: $language) {
                    Text(L("Как в системе", "System default")).tag(Language.system.rawValue)
                    Text("Русский").tag(Language.ru.rawValue)
                    Text("English").tag(Language.en.rawValue)
                }
                .onChange(of: language) { _, _ in
                    NotificationCenter.default.post(name: .languageChanged, object: nil)
                }
            }
            Section(L("Система", "System")) {
                Toggle(L("Запускать при входе в систему", "Launch at login"), isOn: $system.launchAtLogin)
                LabeledContent(L("Доступ к записи экрана", "Screen recording access")) {
                    HStack {
                        Text(system.hasPermission ? L("Разрешён", "Granted") : L("Не разрешён", "Not granted"))
                            .foregroundStyle(system.hasPermission ? .green : .red)
                        Button(L("Открыть настройки…", "Open Settings…")) { Capture.openPrivacySettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { system.refresh() }
    }

    private var recording: some View {
        Form {
            Section(L("Видео", "Video")) {
                Picker(L("Частота кадров", "Frame rate"), selection: $fps) {
                    Text(L("24 к/с", "24 fps")).tag(24)
                    Text(L("30 к/с", "30 fps")).tag(30)
                    Text(L("60 к/с", "60 fps")).tag(60)
                }
                Picker(L("Формат", "Format"), selection: $videoFormat) {
                    Text("MP4").tag("mp4")
                    Text("MOV").tag("mov")
                }
                Picker(L("Кодек", "Codec"), selection: $videoCodec) {
                    Text(L("H.264 (совместимость)", "H.264 (compatible)")).tag("h264")
                    Text(L("HEVC (меньше размер)", "HEVC (smaller files)")).tag("hevc")
                }
                Picker(L("Обратный отсчёт", "Countdown"), selection: $countdown) {
                    Text(L("Нет", "None")).tag(0)
                    Text(L("3 секунды", "3 seconds")).tag(3)
                    Text(L("5 секунд", "5 seconds")).tag(5)
                }
                Toggle(L("Показывать курсор", "Show cursor"), isOn: $showCursor)
                Toggle(L("Подсвечивать клики", "Highlight clicks"), isOn: $showClicks)
                FolderRow(title: L("Папка записей", "Recordings folder"), key: Prefs.Key.videoFolder)
            }
            Section(L("Звук", "Audio")) {
                Toggle(L("Системный звук", "System audio"), isOn: $systemAudio)
                Toggle(L("Микрофон", "Microphone"), isOn: $microphone)
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeys: some View {
        Form {
            Section {
                ForEach(HotAction.allCases, id: \.rawValue) { action in
                    LabeledContent(action.title) {
                        ShortcutField(action: action).frame(width: 170)
                    }
                }
            } footer: {
                Text(L("Нажмите на сочетание, чтобы изменить. Esc — отмена, ⌫ — удалить. Повторное нажатие горячей клавиши записи останавливает запись.", "Click a shortcut to change it. Esc — cancel, ⌫ — remove. Pressing a recording shortcut again stops the recording."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dock icon while windows are open

// Приложение живёт в строке меню; пока открыт редактор или настройки — показываем его в Dock и ⌘Tab.
enum AppPolicy {
    static func windowWillAppear() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    static func windowDidClose() {
        DispatchQueue.main.async {
            let hasWindows = NSApp.windows.contains { w in
                w.isVisible && (w.windowController is EditorController || w.windowController is SettingsWindowController)
            }
            if !hasWindows { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
