#!/bin/zsh
# Builds the widget + menu bar helper and installs it to /Applications.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project SpotifyWidget.xcodeproj -scheme SpotifyWidget -configuration Release \
  -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build | tail -1
pkill -f "Spotify Widget.app/Contents/MacOS" || true
rm -rf "/Applications/Spotify Widget.app"
cp -R "build/Build/Products/Release/Spotify Widget.app" /Applications/
open "/Applications/Spotify Widget.app"
echo "Installed /Applications/Spotify Widget.app"
