#!/bin/bash
# Сборка ear (local).app: компиляция, бандл, копирование сайта, ad-hoc подпись.
set -euo pipefail
cd "$(dirname "$0")"

# ./build.sh            — собрать
# ./build.sh --test     — прогнать проверку нормализации путей и выйти
# ./build.sh --install  — собрать и положить в /Applications
MODE="${1:-}"

if [ "$MODE" = "--test" ]; then
    TMP="$(mktemp -d)"
    swiftc -O Sources/SiteUpdater.swift Tests/normalize-test.swift -o "$TMP/normalize"
    swiftc -O Sources/NothingProtocol.swift Tests/protocol-test.swift -o "$TMP/protocol"
    echo "— нормализация путей"; "$TMP/normalize" || exit 1
    echo; echo "— протокол на записанных кадрах"; exec "$TMP/protocol"
fi

# Откуда берём сайт для вшивания: явный SITE_SRC, иначе свежая копия, которую
# приложение скачало само, иначе старое зеркало от docker-контейнера.
if [ "${SITE_SRC:-}" = "none" ]; then
    SITE_SRC=""                       # осознанная сборка без вшитой копии
elif [ -n "${SITE_SRC:-}" ]; then
    # Явно заданный путь не подменяем молча — иначе соберём не то, что просили.
    [ -d "$SITE_SRC" ] || { echo "SITE_SRC указывает в никуда: $SITE_SRC" >&2; exit 1; }
else
    SITE_SRC="$(ls -d "$HOME/Library/Application Support/ear-local"/site-* 2>/dev/null | sort | tail -1)"
    [ -n "$SITE_SRC" ] && [ -d "$SITE_SRC" ] || SITE_SRC="$HOME/Containers/Nothing Headhone PWA driver/site"
fi
# Стабильная подпись = macOS не переспрашивает разрешение на Bluetooth после
# каждой пересборки. `-` (ad-hoc) меняет cdhash на каждой сборке, и TCC считает
# приложение новым. Создать самоподписанный сертификат: Keychain Access →
# Certificate Assistant → Create a Certificate → Code Signing.
CODESIGN_ID="${CODESIGN_ID:--}"
APP="build/Unofficial driver for Nothing audio devices.app"

# Вшивать чужой сайт необязательно: без него приложение скачает копию при первом
# запуске. Репозиторий поэтому не содержит ни одного файла проекта ear-web.
if [ -d "$SITE_SRC" ]; then
    echo "сайт беру из: $SITE_SRC"
else
    echo "локальной копии сайта нет — приложение скачает её при первом запуске"
    SITE_SRC=""
fi

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Sources/shim.js "$APP/Contents/Resources/shim.js"

# иконка приложения из png проекта
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
    sips -z $sz $sz Sources/icon-1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz*2)) $((sz*2)) Sources/icon-1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
if [ -n "$SITE_SRC" ]; then
    cp -R "$SITE_SRC" "$APP/Contents/Resources/site"
    find "$APP/Contents/Resources/site" -name '._*' -delete
fi

# Универсальный бинарник: нативно на Apple Silicon и работает на Intel.
# swiftc не умеет собирать «толстый» файл сам — компилируем под каждую
# архитектуру и склеиваем.
SLICES=()          # массив, а не строка: в путях есть пробелы
for ARCH in arm64 x86_64; do
    OUT="$APP/Contents/MacOS/ear-local.$ARCH"
    if swiftc -O -target "$ARCH-apple-macos13.0" Sources/SiteUpdater.swift Sources/main.swift -o "$OUT" 2>/dev/null; then
        SLICES+=("$OUT")
    else
        echo "срез $ARCH собрать не удалось, пропускаю" >&2
    fi
done
[ ${#SLICES[@]} -gt 0 ] || { echo "не собралось ни под одну архитектуру" >&2; exit 1; }
lipo -create -output "$APP/Contents/MacOS/ear-local" "${SLICES[@]}"
rm -f "${SLICES[@]}"
codesign --force --deep -s "$CODESIGN_ID" "$APP" >/dev/null 2>&1

echo "готово: $APP ($(du -sh "$APP" | cut -f1)), подпись: $CODESIGN_ID"

if [ "$MODE" = "--install" ]; then
    TARGET="/Applications/$(basename "$APP")"
    # Обновление на месте: bundle id и подпись не меняются, поэтому выданное
    # разрешение на Bluetooth переживает переустановку.
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    echo "установлено: $TARGET"
    echo "запускать отсюда; сборка в build/ остаётся как промежуточный артефакт"
fi
