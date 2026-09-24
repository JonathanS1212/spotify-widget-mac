#!/bin/zsh
# Builds a universal (Apple silicon + Intel) release and packages it as a DMG.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project SpotifyWidget.xcodeproj -scheme SpotifyWidget -configuration Release \
  -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build | tail -1

stage=build/dmg
rm -rf "$stage" "build/Spotify Widget.dmg"
mkdir -p "$stage"
cp -R "build/Build/Products/Release/Spotify Widget.app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Spotify Widget" -srcfolder "$stage" -ov -format UDZO "build/Spotify Widget.dmg" >/dev/null
rm -rf "$stage"
echo "Created $(pwd)/build/Spotify Widget.dmg"
