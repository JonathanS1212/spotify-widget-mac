import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - Spotify bridge (AppleScript)

struct TrackInfo: Equatable {
    var running = false
    var state = "stopped"
    var title = ""
    var artist = ""
    var artworkURL: URL?
    var duration: Double = 0   // seconds
    var position: Double = 0   // seconds
    var isPlaying: Bool { state == "playing" }
}

final class SpotifyModel: ObservableObject {
    @Published var info = TrackInfo()
    private var timer: Timer?
    private let sep = "|~|"

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func run(_ source: String) -> String? {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return err == nil ? result?.stringValue : nil
    }

    func refresh() {
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
        var new = TrackInfo()
        if out == "notrunning" {
            new.running = false
        } else if out == "idle" {
            new.running = true
        } else {
            let p = out.components(separatedBy: sep)
            guard p.count == 6 else { return }
            new.running = true
            new.state = p[0]
            new.title = p[1]
            new.artist = p[2]
            new.artworkURL = URL(string: p[3])
            new.duration = (Double(p[4].replacingOccurrences(of: ",", with: ".")) ?? 0) / 1000
            new.position = Double(p[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        if new != info { info = new }
    }

    private func command(_ cmd: String) {
        _ = run("tell application \"Spotify\" to \(cmd)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refresh() }
    }

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }
}

// MARK: - Views

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

func formatTime(_ s: Double) -> String {
    let t = max(0, Int(s))
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct WidgetView: View {
    @ObservedObject var model: SpotifyModel
    @AppStorage("floatOnTop") var floatOnTop = true

    var body: some View {
        let info = model.info
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary)
                Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.secondary)
                if let url = info.artworkURL {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                }
            }
            .frame(width: 86, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(info.running ? (info.title.isEmpty ? "Nothing playing" : info.title) : "Spotify is closed")
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(info.running ? info.artist : "Press play to open it")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.15))
                        Capsule().fill(Color(red: 0.12, green: 0.84, blue: 0.38))
                            .frame(width: info.duration > 0 ? geo.size.width * min(1, info.position / info.duration) : 0)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)

                HStack {
                    Text(formatTime(info.position))
                    Spacer()
                    Text(formatTime(info.duration))
                }
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)

                HStack(spacing: 26) {
                    Spacer()
                    control("backward.fill", 15) { model.previous() }
                    control(info.isPlaying ? "pause.fill" : "play.fill", 22) { model.playPause() }
                    control("forward.fill", 15) { model.next() }
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(width: 340, height: 116)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Toggle("Keep on Top of Windows", isOn: $floatOnTop)
            Button("Open Spotify") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Spotify.app")) }
            Button(AppDelegate.openAtLogin ? "✓ Open at Login" : "Open at Login") { AppDelegate.toggleOpenAtLogin() }
            Divider()
            Button("Quit Spotify Widget") { NSApp.terminate(nil) }
        }
        .onChange(of: floatOnTop) { _, _ in (NSApp.delegate as? AppDelegate)?.applyLevel() }
    }

    func control(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 30, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window / App

final class ClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: WidgetWindow!
    let model = SpotifyModel()

    static var openAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    static func toggleOpenAtLogin() {
        do {
            if openAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Open at Login failed: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["floatOnTop": true])
        window = WidgetWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 116),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = ClickHostingView(rootView: WidgetView(model: model))
        let restored = window.setFrameUsingName("SpotifyWidget")
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if !restored || !onScreen, let screen = NSScreen.screens.first {  // first = main display with menu bar
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - 340 - 24, y: f.maxY - 116 - 24))
        }
        window.setFrameAutosaveName("SpotifyWidget")
        applyLevel()
        window.orderFrontRegardless()
    }

    func applyLevel() {
        if UserDefaults.standard.bool(forKey: "floatOnTop") {
            window.level = .floating
        } else {
            // Sit on the desktop like a widget (above icons, below app windows)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
        window.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
