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

### Widget + menu bar player

```sh
git clone https://github.com/JonathanS1212/spotify-widget-mac.git
cd spotify-widget-mac/NativeWidget
./build.sh
```

This builds the app, installs it to `/Applications/Spotify Widget.app`, and launches it. Then:

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
| `App/` – menu bar helper | Polls Spotify through AppleScript, saves the track info and resized artwork to a shared App Group folder, and tells WidgetKit to refresh when the track, play state or position changes. It also runs the menu bar player. |
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
- **The widget isn't in the gallery.** Make sure the app is in `/Applications` and has been launched at least once.
- **The widget can't read the helper's data.** `build.sh` signs the app locally, which is enough on most Macs. If it isn't enough on yours, open the project in Xcode, choose your team under *Signing & Capabilities* for both targets, and build from there.

## Disclaimer

This is an unofficial project and isn't affiliated with or endorsed by Spotify.
