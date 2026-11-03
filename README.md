# ShotCap

A lightweight macOS menu bar app for screenshots and screen recording, inspired by Shottr.
Native AppKit + ScreenCaptureKit, no dependencies. Interface in **English** and **Russian**.

[Русская версия ниже ↓](#русский)

## Features

**Screenshots**
- Area selection on a frozen screen with a pixel loupe, HEX color and size readout
- Window capture (click a window, or Space for window mode) with transparent corners
- Full screen, delayed capture (3/5/10 s), capture & pin on top of all windows
- Text recognition (OCR, Russian/English) and QR code reading straight to the clipboard
- Edit an image from the clipboard or a file

**Editor**
- Arrow, line, rectangle, oval, pen, highlighter, text, step counter
- Pixelate, spotlight, crop, color picker, pixel ruler
- Undo/redo, zoom, copy, save as PNG/JPEG, pin, OCR

**Screen recording**
- Selected area (adjustable before start), a single window, a whole app, or the full screen
- System audio, microphone, cursor, click highlighting, 24/30/60 fps, MP4/MOV, H.264/HEVC, countdown
- Stop from the menu bar icon, the floating HUD, or the same shortcut

## Requirements & build

macOS 15 or later, Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh            # builds build/ShotCap.app
./build.sh install    # builds and installs to /Applications
```

On first launch allow ShotCap in **System Settings → Privacy & Security → Screen & System Audio Recording**,
then restart the app. Launch at login is enabled on first run and can be turned off in the menu or Settings.
The interface language (System / English / Russian) is chosen in Settings → General.

## Shortcuts (configurable in Settings)

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

**Selection:** drag — area · click — window · Space — window mode · ↩ — full screen · C — copy color · Esc — cancel.
While recording: ⌥ + click a window records the whole app.

**Editor:** V select · A arrow · L line · R rectangle · O oval · P pen · M highlighter · T text · N counter ·
B pixelate · S spotlight · K crop · I color picker · U ruler. Shift — straight angles/squares.
⌘C copy · ⌘S save · ⇧⌘S save as · ⌘P pin · ⌘Z/⇧⌘Z undo/redo · ⌘+/⌘−/⌘0/⌘9 zoom · ⌫ delete · Esc close.

---

## Русский

Лёгкое приложение в строке меню macOS для скриншотов и записи экрана (аналог Shottr).
Интерфейс на русском и английском — язык меняется в «Настройки → Основные».

**Скриншоты:** выделение области на «замороженном» экране с лупой и цветом, окно, весь экран, с задержкой,
закрепление поверх окон, распознавание текста (OCR) и QR-кодов, редактирование из буфера или файла.

**Редактор:** стрелка, линия, прямоугольник, овал, карандаш, маркер, текст, нумерация, пикселизация,
прожектор, обрезка, пипетка, линейка; отмена/повтор, масштаб, копирование, сохранение PNG/JPEG.

**Запись видео:** область, окно, приложение целиком или весь экран; системный звук, микрофон, курсор,
подсветка кликов, 24/30/60 к/с, MP4/MOV, H.264/HEVC, обратный отсчёт.

**Сборка:** macOS 15+, Command Line Tools. `./build.sh` — сборка, `./build.sh install` — установка в «Программы».
При первом запуске разрешите «Запись экрана и системного аудио» и перезапустите приложение.

**Горячие клавиши:** ⌥⇧1 область · ⌥⇧2 окно · ⌥⇧3 весь экран · ⌥⇧4 OCR · ⌥⇧5 запись области ·
⌥⇧6 запись окна/приложения · ⌥⇧7 запись экрана · ⌥⇧8 скриншот и закрепить. Меняются в Настройках.
