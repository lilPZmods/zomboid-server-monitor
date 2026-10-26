#!/bin/bash
# Builds the app from config.env and installs it in /Applications.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HERE/config.env"
[ -f "$CONFIG" ] || { echo "Missing config.env. Copy config.example.env to config.env and edit it."; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"

xml() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

BUILD="$HERE/build"
APP="$BUILD/$APP_NAME.app"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$APP/Contents/MacOS/$APP_NAME" "$HERE/ZomboidServerMonitor.swift"

swiftc -o "$BUILD/makeicon" "$HERE/MakeIcon.swift"
"$BUILD/makeicon" "$BUILD/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD/AppIcon.iconset"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$(xml "$APP_NAME")</string>
  <key>CFBundleDisplayName</key><string>$(xml "$APP_NAME")</string>
  <key>CFBundleIdentifier</key><string>$(xml "$BUNDLE_ID")</string>
  <key>CFBundleExecutable</key><string>$(xml "$APP_NAME")</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>WWAgentLabel</key><string>$(xml "$AGENT_LABEL")</string>
  <key>WWWorkDir</key><string>$(xml "$WORK_DIR")</string>
  <key>WWWatchCommand</key><string>$(xml "$WATCH_COMMAND")</string>
  <key>WWLogFile</key><string>$(xml "$LOG_FILE")</string>
  <key>WWStatusFile</key><string>$(xml "$STATUS_FILE")</string>
  <key>WWOffCommand</key><string>$(xml "$OFF_COMMAND")</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP" /Applications/
echo "Installed /Applications/$APP_NAME.app"
