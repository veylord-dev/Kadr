# Kadr

**[Русский](#русский) · [English](#english)**

---

## Русский

Приложение в строке меню macOS для скриншотов и записи экрана. Интерфейс на русском и английском.

### Возможности

**Скриншоты**
- Область, окно, весь экран
- Лупа с пикселями, цвет в HEX и размер в пикселях при выделении
- Снимок с задержкой: 3, 5, 10 с
- Закрепление снимка поверх окон
- Распознавание текста (русский, английский) и QR-кодов в буфер обмена
- Открытие изображения из буфера обмена или файла

**Редактор**
- Стрелка, линия, прямоугольник, овал, карандаш, маркер, текст, нумерация
- Пикселизация, прожектор, обрезка, пипетка, линейка
- Отмена и повтор, масштаб, копирование, сохранение в PNG и JPEG

**Запись видео**
- Область, окно, приложение, весь экран
- Системный звук, микрофон, курсор, подсветка кликов
- 24, 30, 60 к/с; MP4, MOV; H.264, HEVC; обратный отсчёт

### Установка

1. Скачайте `Kadr.zip` из [последнего релиза](https://github.com/veylord-dev/Kadr/releases/latest).
2. Распакуйте и перенесите `Kadr.app` в «Программы».
3. При первом запуске: правый клик по приложению → «Открыть». Или в Терминале:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Kadr.app
   ```
4. «Системные настройки → Конфиденциальность и безопасность → Запись экрана и системного аудио» → включите Kadr
   и перезапустите приложение.

Требования: macOS 15+, Apple Silicon или Intel.

Автозапуск при входе включается при первом запуске; отключается в меню приложения или в настройках.
Язык: «Настройки → Основные → Язык».

### Сборка

Нужны Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/veylord-dev/Kadr.git
cd Kadr
./build.sh            # build/Kadr.app
./build.sh install    # установка в /Applications
./build.sh release    # архив build/Kadr.zip
```

### Горячие клавиши

Меняются в настройках.

| Действие | Клавиши |
|---|---|
| Скриншот области | ⌥⇧1 |
| Скриншот окна | ⌥⇧2 |
| Скриншот всего экрана | ⌥⇧3 |
| Распознать текст | ⌥⇧4 |
| Запись области | ⌥⇧5 |
| Запись окна или приложения | ⌥⇧6 |
| Запись всего экрана | ⌥⇧7 |
| Скриншот и закрепить | ⌥⇧8 |

**Выделение:** перетаскивание — область, клик — окно, Space — режим окон, ↩ — весь экран, C — копировать цвет,
Esc — отмена. При записи ⌥ + клик по окну — всё приложение.

**Редактор:** V выбор, A стрелка, L линия, R прямоугольник, O овал, P карандаш, M маркер, T текст, N нумерация,
B пикселизация, S прожектор, K обрезка, I пипетка, U линейка. Shift — углы 45° и квадраты.
⌘C копировать, ⌘S сохранить, ⇧⌘S сохранить как, ⌘P закрепить, ⌘Z / ⇧⌘Z отмена и повтор,
⌘+ / ⌘− / ⌘0 / ⌘9 масштаб, ⌫ удалить, Esc закрыть.

### Код

Swift, AppKit, ScreenCaptureKit, Vision. Без Xcode-проекта и сторонних зависимостей. `build.sh` собирает
универсальный бинарник (arm64 + x86_64).

| Файл | Содержимое |
|---|---|
| `Sources/main.swift` | Точка входа, меню, сценарии скриншота и записи |
| `Sources/Capture.swift` | Захват через ScreenCaptureKit, список окон, сохранение и копирование |
| `Sources/SelectionOverlay.swift` | Выделение области и окна, лупа |
| `Sources/Editor.swift` | Окно редактора, холст, отмена, обрезка |
| `Sources/Annotations.swift` | Модель и отрисовка аннотаций |
| `Sources/Recorder.swift` | Запись через `SCStream` и `SCRecordingOutput` |
| `Sources/PinAndOCR.swift` | Закреплённые снимки, распознавание текста и QR |
| `Sources/Toast.swift` | Уведомления, обратный отсчёт |
| `Sources/Hotkeys.swift` | Глобальные горячие клавиши (Carbon) |
| `Sources/Settings.swift` | Настройки (SwiftUI), автозапуск |
| `Sources/Localization.swift` | Выбор языка, функция `L("ru", "en")` |
| `Tools/make_icon.swift` | Генерация иконки |
| `build.sh` | Сборка, подпись, установка, архив |

---

## English

macOS menu bar app for screenshots and screen recording. Interface in English and Russian.

### Features

**Screenshots**
- Area, window, full screen
- Pixel loupe, HEX color and pixel size while selecting
- Delayed capture: 3, 5, 10 s
- Pin a screenshot on top of other windows
- Text (English, Russian) and QR code recognition to the clipboard
- Open an image from the clipboard or a file

**Editor**
- Arrow, line, rectangle, oval, pen, highlighter, text, step counter
- Pixelate, spotlight, crop, color picker, ruler
- Undo and redo, zoom, copy, save as PNG and JPEG

**Screen recording**
- Area, window, app, full screen
- System audio, microphone, cursor, click highlighting
- 24, 30, 60 fps; MP4, MOV; H.264, HEVC; countdown

### Installation

1. Download `Kadr.zip` from the [latest release](https://github.com/veylord-dev/Kadr/releases/latest).
2. Unzip and move `Kadr.app` to Applications.
3. On first launch: right-click the app → Open. Or in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Kadr.app
   ```
4. System Settings → Privacy & Security → Screen & System Audio Recording → enable Kadr and restart the app.

Requirements: macOS 15+, Apple Silicon or Intel.

Launch at login is enabled on first launch; turn it off in the app menu or in Settings.
Language: Settings → General → Language.

### Build

Requires Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/veylord-dev/Kadr.git
cd Kadr
./build.sh            # build/Kadr.app
./build.sh install    # install to /Applications
./build.sh release    # build/Kadr.zip archive
```

### Shortcuts

Configurable in Settings.

| Action | Keys |
|---|---|
| Capture area | ⌥⇧1 |
| Capture window | ⌥⇧2 |
| Capture full screen | ⌥⇧3 |
| Recognize text | ⌥⇧4 |
| Record area | ⌥⇧5 |
| Record window or app | ⌥⇧6 |
| Record full screen | ⌥⇧7 |
| Capture and pin | ⌥⇧8 |

**Selection:** drag — area, click — window, Space — window mode, ↩ — full screen, C — copy color, Esc — cancel.
While recording, ⌥ + click a window records the whole app.

**Editor:** V select, A arrow, L line, R rectangle, O oval, P pen, M highlighter, T text, N counter, B pixelate,
S spotlight, K crop, I color picker, U ruler. Shift — 45° angles and squares.
⌘C copy, ⌘S save, ⇧⌘S save as, ⌘P pin, ⌘Z / ⇧⌘Z undo and redo, ⌘+ / ⌘− / ⌘0 / ⌘9 zoom, ⌫ delete, Esc close.

### Code

Swift, AppKit, ScreenCaptureKit, Vision. No Xcode project, no third-party dependencies. `build.sh` builds a
universal binary (arm64 + x86_64).

| File | Contents |
|---|---|
| `Sources/main.swift` | Entry point, menu, screenshot and recording flows |
| `Sources/Capture.swift` | ScreenCaptureKit capture, window list, save and copy |
| `Sources/SelectionOverlay.swift` | Area and window selection, loupe |
| `Sources/Editor.swift` | Editor window, canvas, undo, crop |
| `Sources/Annotations.swift` | Annotation model and drawing |
| `Sources/Recorder.swift` | Recording via `SCStream` and `SCRecordingOutput` |
| `Sources/PinAndOCR.swift` | Pinned screenshots, text and QR recognition |
| `Sources/Toast.swift` | Notifications, countdown |
| `Sources/Hotkeys.swift` | Global hotkeys (Carbon) |
| `Sources/Settings.swift` | Settings (SwiftUI), launch at login |
| `Sources/Localization.swift` | Language selection, `L("ru", "en")` helper |
| `Tools/make_icon.swift` | Icon generator |
| `build.sh` | Build, signing, install, archive |
