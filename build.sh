#!/bin/bash
# Builds DiskLens.app from source. Usage:
#   ./build.sh            build into ./build/DiskLens.app
#   ./build.sh --install  also copy it to /Applications and launch it
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift not found. Install Apple's command line tools first:  xcode-select --install"
  exit 1
fi

echo "› Compiling (release)…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/DiskLens"
APP="build/DiskLens.app"

echo "› Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DiskLens"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon-1024.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# Ad-hoc signature so macOS will run it locally (and remember its privacy permissions).
codesign --force --deep --sign - "$APP" >/dev/null
echo "✓ Built $(pwd)/$APP"

if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/DiskLens.app"
  osascript -e 'tell application "DiskLens" to quit' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "✓ Installed to $DEST"
  open "$DEST"
fi
