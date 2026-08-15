#!/bin/zsh
# Builds ClaudeSessions.app (menu bar app, no dock icon).
set -e

# Stamp the release tag into the bundle so the app can tell when it is out of date.
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
VERSION=${VERSION:-0.0.0}
# --disable-sandbox: SwiftPM cannot nest its own sandbox inside Homebrew's build sandbox.
# UNIVERSAL=1 builds arm64 + x86_64, for the prebuilt zip that Intel Macs download.
if [ -n "$UNIVERSAL" ]; then
  swift build -c release --disable-sandbox --arch arm64 --arch x86_64
  BIN=.build/apple/Products/Release/ClaudeSessions
else
  swift build -c release --disable-sandbox
  BIN=.build/release/ClaudeSessions
fi

APP="ClaudeSessions.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ClaudeSessions</string>
  <key>CFBundleIdentifier</key><string>dev.local.claudesessions</string>
  <key>CFBundleName</key><string>Claude Sessions</string>
  <key>CFBundleIconFile</key><string>ClaudeSessions</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>__VERSION__</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
sed -i '' "s/__VERSION__/$VERSION/g" "$APP/Contents/Info.plist"

# Finder, alerts and Login Items all show this. Rendered from the same sprite as the menu bar.
mkdir -p "$APP/Contents/Resources"
ICONSET=$(mktemp -d)/ClaudeSessions.iconset
swift tools/makeicon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ClaudeSessions.icns"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Built $APP — run: open $APP"
