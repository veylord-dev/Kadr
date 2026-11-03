#!/bin/zsh
# Собирает Kadr.app в ./build; `./build.sh install` — ещё и ставит в /Applications.
set -e
cd "$(dirname "$0")"

APP=build/Kadr.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swift Tools/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Универсальный бинарник: Apple Silicon + Intel.
for ARCH in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $ARCH-apple-macos15 -o build/Kadr-$ARCH Sources/*.swift
done
lipo -create build/Kadr-arm64 build/Kadr-x86_64 -output "$APP/Contents/MacOS/Kadr"
rm build/Kadr-arm64 build/Kadr-x86_64

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Kadr</string>
    <key>CFBundleDisplayName</key><string>Kadr</string>
    <key>CFBundleIdentifier</key><string>dev.veylord.kadr</string>
    <key>CFBundleExecutable</key><string>Kadr</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Kadr записывает звук с микрофона во время записи экрана.</string>
    <key>NSScreenCaptureUsageDescription</key><string>Kadr делает скриншоты и записывает видео с экрана.</string>
</dict>
</plist>
PLIST

# Стабильная подпись (если есть сертификат разработчика) сохраняет разрешение на запись экрана между сборками.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID/ {print $2; exit}')
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    # Без сертификата требование привязываем к идентификатору, а не к хешу сборки,
    # чтобы разрешение на запись экрана не слетало после каждой пересборки.
    codesign --force --sign - -r='designated => identifier "dev.veylord.kadr"' "$APP"
fi
echo "Готово: $APP (подпись: ${IDENTITY:-ad-hoc})"

if [[ "$1" == "release" ]]; then
    # Архив для GitHub Releases (ditto сохраняет подпись и атрибуты).
    ditto -c -k --keepParent "$APP" build/Kadr.zip
    echo "Архив: build/Kadr.zip"
fi

if [[ "$1" == "install" ]]; then
    DEST=/Applications/Kadr.app
    pkill -x Kadr 2>/dev/null && sleep 0.5 || true
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    # Одна копия приложения — чтобы автозапуск и разрешения относились к /Applications.
    rm -rf "$APP"
    open "$DEST"
    echo "Установлено: $DEST"
fi
