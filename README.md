# Spotify Widget for macOS

A native macOS widget and menu bar mini player for the Spotify desktop app. It shows the current track with album art and a live progress bar, and lets you play, pause and skip without switching to Spotify.

## Features

- **Desktop / Notification Center widget** (small and medium sizes)
  - Album art over a blurred background of the same art
  - Song title, artist, and a progress bar that updates on its own
  - Interactive previous, play/pause and next buttons
  - Click anywhere else on the widget to open Spotify
- **Menu bar player**
  - Current song name in the menu bar (can be turned off)
  - Click it for a panel with album art, progress and controls
  - Open-at-login toggle
- **Album art wallpaper** (optional, off by default): like the iPhone lock screen, the current album cover appears on the desktop over a blurred version of itself, on every display and Space, and cross-fades when the track changes. It is drawn behind your icons and widgets, so your real wallpaper is never changed and comes back as soon as Spotify stops or you turn the option off. Turn it on from the menu bar panel.
- **Floating player** (optional, standalone): a draggable mini player window that works without Xcode

## Requirements

- macOS 14 (Sonoma) or later
- The [Spotify desktop app](https://www.spotify.com/download/mac/)
- Xcode (to build the widget). The floating player only needs the Xcode Command Line Tools.

## Install

### Download

Get **Spotify Widget.dmg** from the [latest release](https://github.com/JonathanS1212/spotify-widget-mac/releases/latest), open it, and drag **Spotify Widget** into **Applications**. It runs on Apple silicon and Intel Macs.

The app isn't notarized, so macOS blocks it the first time. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or run this in Terminal after copying it to Applications:

```sh
xattr -cr "/Applications/Spotify Widget.app"
```

Always run it from **Applications**, not from inside the DMG. Then follow the two setup steps under "Build from source" below.

### Build from source (widget + menu bar player)

```sh
git clone https://github.com/JonathanS1212/spotify-widget-mac.git
cd spotify-widget-mac/NativeWidget
./build.sh
```

This builds the app, installs it to `/Applications/Spotify Widget.app`, and launches it. To package a universal DMG instead, run `./make-dmg.sh`; it writes `build/Spotify Widget.dmg`. Then:

1. When macOS asks whether **Spotify Widget** may control **Spotify**, click **OK**.
2. Right-click the desktop → **Edit Widgets…** → search **Spotify** → drag a widget onto the desktop or into Notification Center.

The helper app turns on **Open at Login** the first time it runs so the widget keeps updating after a restart. You can turn this off from the menu bar panel.

### Floating player only

```sh
cd spotify-widget-mac/FloatingPlayer
./build.sh
open ~/Applications/"Spotify Widget.app"
```

Right-click the player to keep it on top, open Spotify, or quit.

> Note: both builds use the name "Spotify Widget". Use one or the other, or rename one of them.

## How it works

Widgets run in a sandbox and can't talk to Spotify directly, so the project has two parts:

| Part | What it does |
| --- | --- |
| `App/` – menu bar helper | Polls Spotify through AppleScript, saves the track info and resized artwork to a shared folder in `~/Library/Application Support/Spotify Widget`, and tells WidgetKit to refresh when the track, play state or position changes. It also runs the menu bar player. |
| `Widget/` – WidgetKit extension | Reads the shared state and draws the widget. The buttons are App Intents. They leave a command in the shared folder and post a Darwin notification, and the helper forwards the command to Spotify. |
| `Shared/` | The state model and shared file paths used by both parts. |

The progress bar uses `ProgressView(timerInterval:)`, so it moves smoothly without the widget having to reload every second.

## Project layout

```
NativeWidget/
  project.yml              XcodeGen spec (the .xcodeproj is generated from it)
  SpotifyWidget.xcodeproj  Ready to open in Xcode
  App/                     Menu bar helper app
  Widget/                  Widget extension
  Shared/                  Code shared by both
  build.sh                 Build + install script
FloatingPlayer/
  main.swift               Standalone floating mini player
  build.sh                 Builds it with swiftc
```

To regenerate the Xcode project after editing `project.yml`, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and run `xcodegen generate` in `NativeWidget/`.

## Troubleshooting

- **The widget says "Spotify is closed" or never updates.** Check that the menu bar helper is running (look for the music-note icon). Also check System Settings → Privacy & Security → Automation → Spotify Widget → Spotify is on.
- **The menu bar icon is missing.** macOS hides menu bar icons that don't fit, which happens a lot on MacBooks with a notch. Open **Spotify Widget** from Applications again to get the same controls and settings in a window, and turn off "Show song in menu bar" to make the icon smaller.
- **The widget isn't in the gallery.** Make sure the app is in `/Applications` and has been launched at least once.
- **The widget can't read the helper's data.** The helper saves the track info to `~/Library/Application Support/Spotify Widget/`. Check that `state.json` there updates when the song changes. If you just updated from an older version, remove the widget and add it again.

## Disclaimer

This is an unofficial project and isn't affiliated with or endorsed by Spotify.
