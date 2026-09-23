#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Spotify Widget.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Spotify Widget</string>
  <key>CFBundleIdentifier</key><string>com.jon.spotifywidget</string>
  <key>CFBundleExecutable</key><string>SpotifyWidget</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Spotify Widget needs to control Spotify to show the current track and play/pause/skip.</string>
</dict></plist>
PLIST
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/SpotifyWidget"
codesign --force -s - "$APP"
echo "Built: $APP"
