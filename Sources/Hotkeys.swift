import AppKit
import Carbon.HIToolbox

// MARK: - Shortcut

struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Shortcut.keyName(keyCode)
    }

    // Символ для keyEquivalent в меню (только для отображения).
    var menuKey: String {
        let name = Shortcut.keyName(keyCode)
        return name.count == 1 ? name.lowercased() : ""
    }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
        ]
        if let name = special[Int(code)] { return name }
        return layoutCharacter(code)?.uppercased() ?? "#\(code)"
    }

    // Символ клавиши в ASCII-раскладке, чтобы в меню было «S», а не «Ы».
    private static func layoutCharacter(_ code: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &dead, chars.count, &len, &chars)
            guard status == noErr, len > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: len)
        }
    }
}

// MARK: - Actions with hotkeys

enum HotAction: String, CaseIterable {
    case captureArea, captureWindow, captureScreen, captureOCR, capturePin
    case recordArea, recordWindow, recordScreen

    var title: String {
        switch self {
        case .captureArea: return L("Скриншот области", "Capture area")
        case .captureWindow: return L("Скриншот окна", "Capture window")
        case .captureScreen: return L("Скриншот всего экрана", "Capture full screen")
        case .captureOCR: return L("Распознать текст (OCR)", "Recognize text (OCR)")
        case .capturePin: return L("Скриншот и закрепить", "Capture and pin")
        case .recordArea: return L("Запись области", "Record area")
        case .recordWindow: return L("Запись окна / приложения", "Record window / app")
        case .recordScreen: return L("Запись всего экрана", "Record full screen")
        }
    }

    private var defaultShortcut: Shortcut {
        let codes: [HotAction: Int] = [
            .captureArea: kVK_ANSI_1, .captureWindow: kVK_ANSI_2, .captureScreen: kVK_ANSI_3,
            .captureOCR: kVK_ANSI_4, .recordArea: kVK_ANSI_5, .recordWindow: kVK_ANSI_6,
            .recordScreen: kVK_ANSI_7, .capturePin: kVK_ANSI_8,
        ]
        return Shortcut(keyCode: UInt32(codes[self]!), modifiers: [.option, .shift])
    }

    private var defaultsKey: String { "hotkey.\(rawValue)" }

    // Хранится как "code:mods", пустая строка — сочетание удалено.
    var shortcut: Shortcut? {
        get {
            guard let s = UserDefaults.standard.string(forKey: defaultsKey) else { return defaultShortcut }
            let parts = s.split(separator: ":").compactMap { UInt($0) }
            guard parts.count == 2 else { return nil }
            return Shortcut(keyCode: UInt32(parts[0]), modifiers: NSEvent.ModifierFlags(rawValue: parts[1]))
        }
        nonmutating set {
            let value = newValue.map { "\($0.keyCode):\($0.modifiers.rawValue)" } ?? ""
            UserDefaults.standard.set(value, forKey: defaultsKey)
        }
    }
}

extension Notification.Name {
    static let hotkeysChanged = Notification.Name("KadrHotkeysChanged")
}

// MARK: - Global hotkeys (Carbon, не требует прав Accessibility)

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var handler: ((HotAction) -> Void)?
    private var refs: [HotAction: EventHotKeyRef] = [:]

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let all = HotAction.allCases
            let index = Int(hk.id)
            if index < all.count {
                DispatchQueue.main.async { HotKeyCenter.shared.handler?(all[index]) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func registerAll() {
        HotAction.allCases.forEach(register)
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    func register(_ action: HotAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        guard let s = action.shortcut, let index = HotAction.allCases.firstIndex(of: action) else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5348_4350), id: UInt32(index)) // 'SHCP'
        if RegisterEventHotKey(s.keyCode, s.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs[action] = ref
        }
    }
}

// MARK: - Shortcut recorder button (для настроек)

final class ShortcutButton: NSButton {
    let hotAction: HotAction
    private var monitor: Any?
    private static weak var active: ShortcutButton?

    init(action: HotAction) {
        hotAction = action
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        self.action = #selector(clicked)
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutsChanged), name: .hotkeysChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        title = hotAction.shortcut?.displayString ?? "—"
    }

    @objc private func clicked() {
        if monitor != nil { stop(); return }
        if let other = Self.active, other !== self { other.stop() }
        Self.active = self
        title = L("Нажмите сочетание…", "Press shortcut…")
        // Иначе Carbon перехватит уже занятое сочетание раньше нас.
        HotKeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let isFKey = Shortcut.keyName(UInt32(code)).hasPrefix("F") && Shortcut.keyName(UInt32(code)).count > 1
        switch code {
        case kVK_Escape where mods.isEmpty:
            stop()
        case kVK_Delete where mods.isEmpty, kVK_ForwardDelete where mods.isEmpty:
            hotAction.shortcut = nil
            stop()
        default:
            guard !mods.isEmpty || isFKey else { NSSound.beep(); return }
            let new = Shortcut(keyCode: UInt32(code), modifiers: mods)
            // Убираем это же сочетание у других действий.
            for other in HotAction.allCases where other != hotAction && other.shortcut == new { other.shortcut = nil }
            hotAction.shortcut = new
            stop()
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyCenter.shared.registerAll()
        NotificationCenter.default.post(name: .hotkeysChanged, object: nil)
        refresh()
    }

    // Закрыли окно, не нажав сочетание, — возвращаем горячие клавиши.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, monitor != nil { stop() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResigned),
                                                   name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    @objc private func windowResigned() {
        if monitor != nil { stop() }
    }

    @objc private func shortcutsChanged() {
        if monitor == nil { refresh() }
    }
}
