# ShotCap

**[Русский](#русский) · [English](#english)**

---

## Русский

Лёгкое приложение в строке меню macOS для скриншотов и записи экрана (аналог Shottr).
Нативное: AppKit + ScreenCaptureKit, без сторонних зависимостей. Интерфейс на русском и английском.

### Возможности

**Скриншоты**
- Выделение области на «замороженном» экране: лупа с пикселями, цвет в HEX, размер в пикселях
- Снимок окна (клик по окну или Space — режим окон) с прозрачными скруглёнными углами
- Весь экран, снимок с задержкой (3/5/10 с), снимок с закреплением поверх всех окон
- Распознавание текста (OCR, русский/английский) и QR-кодов сразу в буфер обмена
- Редактирование картинки из буфера обмена или файла

**Редактор**
- Стрелка, линия, прямоугольник, овал, карандаш, маркер, текст, нумерация шагов
- Пикселизация, прожектор, обрезка, пипетка, линейка в пикселях
- Отмена/повтор, масштаб, копирование, сохранение PNG/JPEG, закрепление, OCR

**Запись видео**
- Выделенная область (рамку можно подвинуть до старта), отдельное окно, приложение целиком или весь экран
- Системный звук, микрофон, курсор, подсветка кликов, 24/30/60 к/с, MP4/MOV, H.264/HEVC, обратный отсчёт
- Остановка кликом по значку в строке меню, кнопкой «Стоп» на панели или той же горячей клавишей

### Установка

**Готовое приложение (рекомендуется)**

1. Скачайте `ShotCap.zip` из [последнего релиза](https://github.com/veylord-dev/ShotCap/releases/latest).
2. Распакуйте архив и перенесите **ShotCap.app** в папку «Программы».
3. Приложение не заверено Apple, поэтому при первом запуске нажмите на него **правой кнопкой → «Открыть»** и
   подтвердите. Либо выполните в Терминале:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ShotCap.app
   ```
4. Разрешите доступ: **Системные настройки → Конфиденциальность и безопасность → Запись экрана и системного
   аудио** → включите ShotCap, затем перезапустите приложение.
5. Значок появится в строке меню. Автозапуск при входе в систему включается сам; выключить можно в меню значка
   или в Настройках. Язык интерфейса — «Настройки → Основные → Язык».

Требуется macOS 15 или новее, Apple Silicon или Intel.

**Сборка из исходников**

Нужны только Command Line Tools (`xcode-select --install`), Xcode не требуется.

```bash
git clone https://github.com/veylord-dev/ShotCap.git
cd ShotCap
./build.sh            # собрать build/ShotCap.app
./build.sh install    # собрать и установить в /Applications
./build.sh release    # собрать архив build/ShotCap.zip для релиза
```

### Горячие клавиши (меняются в Настройках)

| Действие | Клавиши |
|---|---|
| Скриншот области | ⌥⇧1 |
| Скриншот окна | ⌥⇧2 |
| Скриншот всего экрана | ⌥⇧3 |
| Распознать текст (OCR) | ⌥⇧4 |
| Запись области | ⌥⇧5 |
| Запись окна / приложения | ⌥⇧6 |
| Запись всего экрана | ⌥⇧7 |
| Скриншот и закрепить | ⌥⇧8 |

**Выделение:** перетаскивание — область · клик — окно · Space — режим окон · ↩ — весь экран ·
C — скопировать цвет · Esc — отмена. При записи ⌥ + клик по окну записывает всё приложение.

**Редактор:** V выбор · A стрелка · L линия · R прямоугольник · O овал · P карандаш · M маркер · T текст ·
N нумерация · B пикселизация · S прожектор · K обрезка · I пипетка · U линейка. Shift — ровные углы и квадраты.
⌘C копировать · ⌘S сохранить · ⇧⌘S сохранить как · ⌘P закрепить · ⌘Z/⇧⌘Z отмена/повтор ·
⌘+/⌘−/⌘0/⌘9 масштаб · ⌫ удалить · Esc закрыть.

### О коде

Swift, один исполняемый файл без Xcode-проекта и зависимостей. Собирается `swiftc` из `build.sh` в
универсальный бинарник (arm64 + x86_64).

| Файл | Что внутри |
|---|---|
| `Sources/main.swift` | Точка входа, меню в строке меню, обработка действий, сценарии скриншота и записи |
| `Sources/Capture.swift` | Снимки через ScreenCaptureKit, список окон, геометрия экранов, сохранение и копирование изображений |
| `Sources/SelectionOverlay.swift` | Полноэкранное выделение: область, окно, лупа, рамка с ручками перед записью |
| `Sources/Editor.swift` | Окно редактора, панель инструментов, холст, отмена/повтор, обрезка |
| `Sources/Annotations.swift` | Инструменты и модель аннотаций, их отрисовка и итоговый рендер картинки |
| `Sources/Recorder.swift` | Запись видео через `SCStream` + `SCRecordingOutput`, рамка области и панель с таймером |
| `Sources/PinAndOCR.swift` | Закреплённые окна-снимки, распознавание текста и QR (Vision), окно с текстом |
| `Sources/Toast.swift` | Всплывающие уведомления и обратный отсчёт |
| `Sources/Hotkeys.swift` | Глобальные горячие клавиши (Carbon) и поле записи сочетаний |
| `Sources/Settings.swift` | Настройки (SwiftUI), значения по умолчанию, автозапуск |
| `Sources/Localization.swift` | Выбор языка и функция `L("рус", "eng")` для строк интерфейса |
| `Tools/make_icon.swift` | Генерация иконки приложения |
| `build.sh` | Сборка, подпись, установка и архив для релиза |

**Как устроено**
- Скриншот: сначала снимаются все экраны в полном разрешении, затем поверх показывается «замороженная» картинка
  для выделения — поэтому лупа точна до пикселя, а результат обрезается из уже готового снимка.
- Аннотации — значения (`struct`), поэтому отмена хранит просто копии массива. Один и тот же код рисует их
  на холсте и в итоговом изображении в полном разрешении.
- Запись: `SCRecordingOutput` сам пишет файл с видео и звуком; окна самого ShotCap исключены из кадра.
- Перевод: каждая строка интерфейса записана как `L("русский", "English")`; при смене языка меню и настройки
  перестраиваются сразу.

---

## English

A lightweight macOS menu bar app for screenshots and screen recording, inspired by Shottr.
Native AppKit + ScreenCaptureKit, no third-party dependencies. Interface in English and Russian.

### Features

**Screenshots**
- Area selection on a frozen screen with a pixel loupe, HEX color and pixel size readout
- Window capture (click a window, or Space for window mode) with transparent rounded corners
- Full screen, delayed capture (3/5/10 s), capture and pin on top of all windows
- Text recognition (OCR, English/Russian) and QR code reading straight to the clipboard
- Edit an image from the clipboard or a file

**Editor**
- Arrow, line, rectangle, oval, pen, highlighter, text, step counter
- Pixelate, spotlight, crop, color picker, pixel ruler
- Undo/redo, zoom, copy, save as PNG/JPEG, pin, OCR

**Screen recording**
- Selected area (adjustable before start), a single window, a whole app, or the full screen
- System audio, microphone, cursor, click highlighting, 24/30/60 fps, MP4/MOV, H.264/HEVC, countdown
- Stop from the menu bar icon, the Stop button on the floating panel, or the same shortcut

### Installation

**Prebuilt app (recommended)**

1. Download `ShotCap.zip` from the [latest release](https://github.com/veylord-dev/ShotCap/releases/latest).
2. Unzip it and move **ShotCap.app** to the Applications folder.
3. The app is not notarized by Apple, so on first launch **right-click it → Open** and confirm.
   Or run in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ShotCap.app
   ```
4. Grant access: **System Settings → Privacy & Security → Screen & System Audio Recording** → turn on ShotCap,
   then restart the app.
5. The icon appears in the menu bar. Launch at login is enabled automatically; turn it off from the menu or in
   Settings. Interface language is in Settings → General → Language.

Requires macOS 15 or later, Apple Silicon or Intel.

**Build from source**

Only the Command Line Tools are needed (`xcode-select --install`); Xcode is not required.

```bash
git clone https://github.com/veylord-dev/ShotCap.git
cd ShotCap
./build.sh            # build build/ShotCap.app
./build.sh install    # build and install to /Applications
./build.sh release    # build the build/ShotCap.zip release archive
```

### Shortcuts (configurable in Settings)

| Action | Keys |
|---|---|
| Capture area | ⌥⇧1 |
| Capture window | ⌥⇧2 |
| Capture full screen | ⌥⇧3 |
| Recognize text (OCR) | ⌥⇧4 |
| Record area | ⌥⇧5 |
| Record window / app | ⌥⇧6 |
| Record full screen | ⌥⇧7 |
| Capture and pin | ⌥⇧8 |

**Selection:** drag — area · click — window · Space — window mode · ↩ — full screen · C — copy color ·
Esc — cancel. While recording, ⌥ + click a window records the whole app.

**Editor:** V select · A arrow · L line · R rectangle · O oval · P pen · M highlighter · T text · N counter ·
B pixelate · S spotlight · K crop · I color picker · U ruler. Shift — straight angles and squares.
⌘C copy · ⌘S save · ⇧⌘S save as · ⌘P pin · ⌘Z/⇧⌘Z undo/redo · ⌘+/⌘−/⌘0/⌘9 zoom · ⌫ delete · Esc close.

### About the code

Swift, a single executable with no Xcode project and no dependencies. `build.sh` compiles it with `swiftc` into
a universal binary (arm64 + x86_64).

| File | Contents |
|---|---|
| `Sources/main.swift` | Entry point, menu bar menu, action handling, screenshot and recording flows |
| `Sources/Capture.swift` | ScreenCaptureKit captures, window list, screen geometry, image save and copy |
| `Sources/SelectionOverlay.swift` | Full-screen selection: area, window, loupe, adjustable frame before recording |
| `Sources/Editor.swift` | Editor window, toolbar, canvas, undo/redo, crop |
| `Sources/Annotations.swift` | Tools and annotation model, drawing and final image rendering |
| `Sources/Recorder.swift` | Recording via `SCStream` + `SCRecordingOutput`, area frame and timer panel |
| `Sources/PinAndOCR.swift` | Pinned screenshot windows, text and QR recognition (Vision), text panel |
| `Sources/Toast.swift` | Toast notifications and countdown |
| `Sources/Hotkeys.swift` | Global hotkeys (Carbon) and the shortcut recorder control |
| `Sources/Settings.swift` | Settings (SwiftUI), defaults, launch at login |
| `Sources/Localization.swift` | Language selection and the `L("ru", "en")` helper for UI strings |
| `Tools/make_icon.swift` | App icon generator |
| `build.sh` | Build, signing, install and release archive |

**How it works**
- Screenshots: all displays are captured at full resolution first, then shown frozen for selection — so the loupe
  is pixel-accurate and the result is cropped from the captured image.
- Annotations are value types (`struct`), so undo just stores copies of the array. The same code draws them on
  the canvas and into the full-resolution output image.
- Recording: `SCRecordingOutput` writes the video and audio file directly; ShotCap's own windows are excluded.
- Localization: every UI string is written as `L("русский", "English")`; changing the language rebuilds the menu
  and settings immediately.
