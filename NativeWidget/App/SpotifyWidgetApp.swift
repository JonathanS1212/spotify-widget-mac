import SwiftUI
import WidgetKit
import ServiceManagement

@main
struct SpotifyWidgetApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var monitor = SpotifyMonitor.shared
    @AppStorage("showTitleInMenuBar") private var showTitle = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarPlayer(monitor: monitor)
        } label: {
            let s = monitor.state
            Image(systemName: s.isPlaying ? "music.note" : "pause.circle")
            if showTitle && s.running && !s.title.isEmpty {
                Text(Self.truncate("\(s.title) · \(s.artist)", 34))
            }
        }
        .menuBarExtraStyle(.window)
    }

    static func truncate(_ text: String, _ max: Int) -> String {
        text.count > max ? String(text.prefix(max - 1)) + "…" : text
    }
}

/// The menu bar icon can end up hidden (behind the notch, or when the menu bar is full), so opening the app
/// again from Finder or Launchpad shows the same player in a regular window. It also shows once on first launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func showWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: MenuBarPlayer(monitor: .shared)))
            w.title = "Spotify Widget"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private let spotifyGreen = Color(red: 0.12, green: 0.84, blue: 0.38)

private func formatTime(_ s: Double) -> String {
    let t = max(0, Int(s))
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct MenuBarPlayer: View {
    @ObservedObject var monitor: SpotifyMonitor
    @AppStorage("showTitleInMenuBar") private var showTitle = true

    var body: some View {
        let s = monitor.state
        VStack(alignment: .leading, spacing: 12) {
            if s.running && !s.title.isEmpty {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary)
                        if let art = monitor.artwork {
                            Image(nsImage: art).resizable().scaledToFill()
                        } else {
                            Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Text(s.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let pos = s.position(at: ctx.date)
                    VStack(spacing: 3) {
                        ProgressView(value: min(pos, max(s.duration, 1)), total: max(s.duration, 1))
                            .progressViewStyle(.linear).tint(spotifyGreen)
                        HStack {
                            Text(formatTime(pos))
                            Spacer()
                            Text(formatTime(s.duration))
                        }
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 28) {
                    Spacer()
                    control("backward.fill", 16) { monitor.handle("previous") }
                    control(s.isPlaying ? "pause.circle.fill" : "play.circle.fill", 34) { monitor.handle("playpause") }
                    control("forward.fill", 16) { monitor.handle("next") }
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(spotifyGreen)
                    Text(s.running ? "Nothing playing" : "Spotify is closed").font(.headline)
                    Button("Open Spotify") { monitor.handle("open") }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }

            Divider()
            Toggle("Show song in menu bar", isOn: $showTitle)
            Toggle("Album art as wallpaper", isOn: Binding(get: { monitor.albumWallpaper }, set: { monitor.setAlbumWallpaper($0) }))
            Toggle("Open at login", isOn: Binding(get: { monitor.openAtLogin }, set: { monitor.setOpenAtLogin($0) }))
            HStack {
                Button("Open Spotify") { monitor.handle("open") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 290)
    }

    func control(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

final class SpotifyMonitor: ObservableObject {
    static let shared = SpotifyMonitor()

    @Published private(set) var state = PlayerState()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var albumWallpaper = UserDefaults.standard.bool(forKey: "albumWallpaper")
    private var timer: Timer?
    private let sep = "|~|"

    private init() {
        state = PlayerState.load()
        if state.artworkSource != nil { artwork = NSImage(contentsOf: Shared.artworkURL) }
        if !UserDefaults.standard.bool(forKey: "didSetupLogin") {
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
            setOpenAtLogin(true)
        }
        // Spotify announces every track and play/pause change, so we don't have to wait for the next poll.
        DistributedNotificationCenter.default().addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.poll()
            // Spotify can post this a moment before AppleScript reports the new track.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.poll() }
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { SpotifyMonitor.shared.checkCommandFile() }
        }, Shared.commandNotification as CFString, nil, .deliverImmediately)
        DispatchQueue.main.async { self.poll(force: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkCommandFile()
            self?.poll()
        }
    }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Open at Login failed: \(error)")
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setAlbumWallpaper(_ on: Bool) {
        albumWallpaper = on
        UserDefaults.standard.set(on, forKey: "albumWallpaper")
        if on { poll(force: true) } else { AlbumWallpaper.shared.hide() }
    }

    // MARK: Commands

    func checkCommandFile() {
        guard let cmd = try? String(contentsOf: Shared.commandURL, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: Shared.commandURL)
        handle(cmd.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func handle(_ cmd: String) {
        switch cmd {
        case "playpause": run("tell application \"Spotify\" to playpause")
        case "next": run("tell application \"Spotify\" to next track")
        case "previous": run("tell application \"Spotify\" to previous track")
        case "open":
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        default: return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.poll(force: true) }
    }

    @discardableResult
    private func run(_ source: String) -> String? {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { NSLog("AppleScript error: \(err)") }
        return err == nil ? result?.stringValue : nil
    }

    // MARK: Polling

    private func poll(force: Bool = false) {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                try
                    set t to current track
                    return (player state as string) & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (artwork url of t) & "\(sep)" & (duration of t as string) & "\(sep)" & (player position as string)
                on error
                    return "idle"
                end try
            end tell
        else
            return "notrunning"
        end if
        """
        guard let out = run(script) else { return }

        var new = PlayerState()
        new.artworkSource = state.artworkSource
        var artURL: String?
        if out != "notrunning" {
            new.running = true
            let p = out.components(separatedBy: sep)
            if out != "idle", p.count == 6 {
                new.isPlaying = p[0] == "playing"
                new.title = p[1]
                new.artist = p[2]
                artURL = p[3]
                new.duration = (Double(p[4].replacingOccurrences(of: ",", with: ".")) ?? 0) / 1000
                new.position = Double(p[5].replacingOccurrences(of: ",", with: ".")) ?? 0
            }
        }

        // Only push to the widget when something meaningful changed (track, play state, or a seek);
        // the widget animates the progress bar on its own in between.
        let drift = abs(state.position(at: Date()) - new.position)
        let changed = new.running != state.running || new.isPlaying != state.isPlaying
            || new.title != state.title || new.artist != state.artist || drift > 3
        let newArt = artURL.flatMap { $0.isEmpty || $0 == state.artworkSource ? nil : $0 }
        if force || changed {
            state = new
            state.save()
            // On a new track, reload once the cover is in so the widget doesn't show the new title with the
            // old art (WidgetKit throttles reloads, so a second one can lag). Fall back if the download stalls.
            if newArt == nil { WidgetCenter.shared.reloadAllTimelines() } else { scheduleFallbackReload() }
        }
        if let newArt { downloadArtwork(newArt) }
        if albumWallpaper { AlbumWallpaper.shared.show(new.title.isEmpty ? nil : artURL) }
    }

    private var downloading: String?
    private var fallbackReload: DispatchWorkItem?

    private func scheduleFallbackReload() {
        fallbackReload?.cancel()
        let work = DispatchWorkItem { WidgetCenter.shared.reloadAllTimelines() }
        fallbackReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func downloadArtwork(_ urlString: String) {
        guard downloading != urlString, let url = URL(string: urlString) else { return }
        downloading = urlString
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let jpeg = data.flatMap(NSImage.init(data:)).flatMap { Self.jpeg($0, side: 300) }
            DispatchQueue.main.async {
                self.downloading = nil
                self.fallbackReload?.cancel()
                guard let jpeg, (try? jpeg.write(to: Shared.artworkURL, options: .atomic)) != nil else {
                    return WidgetCenter.shared.reloadAllTimelines()
                }
                self.state.artworkSource = urlString
                self.state.save()
                self.artwork = NSImage(data: jpeg)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }.resume()
    }

    private static func jpeg(_ image: NSImage, side: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
