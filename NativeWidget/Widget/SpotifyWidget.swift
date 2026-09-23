import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Intent (interactive buttons)

struct SpotifyCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Control Spotify"
    static var isDiscoverable = false

    @Parameter(title: "Command") var command: String

    init() {}
    init(_ command: String) { self.command = command }

    func perform() async throws -> some IntentResult {
        // Optimistically flip play/pause so the button responds instantly.
        if command == "playpause" {
            var s = PlayerState.load()
            s.position = s.position(at: Date())
            s.capturedAt = Date()
            s.isPlaying.toggle()
            s.save()
        }
        Shared.send(command)
        try? await Task.sleep(nanoseconds: 500_000_000)  // give the helper app time to update
        return .result()
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let state: PlayerState
    let artwork: NSImage?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        var s = PlayerState()
        s.running = true; s.title = "Song Title"; s.artist = "Artist"; s.duration = 200; s.position = 70
        return Entry(date: .now, state: s, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let e = current()
        completion(context.isPreview && e.state.title.isEmpty ? placeholder(in: context) : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let e = current()
        var policy = TimelineReloadPolicy.never
        if e.state.isPlaying, e.state.duration > 0 {
            // Fallback refresh at the end of the song in case the helper's reload is throttled.
            let end = e.state.capturedAt.addingTimeInterval(e.state.duration - e.state.position + 1)
            policy = .after(max(end, Date().addingTimeInterval(10)))
        }
        completion(Timeline(entries: [e], policy: policy))
    }

    private func current() -> Entry {
        let s = PlayerState.load()
        let art = s.artworkSource != nil ? NSImage(contentsOf: Shared.artworkURL) : nil
        return Entry(date: .now, state: s, artwork: art)
    }
}

// MARK: - Views

private let spotifyGreen = Color(red: 0.12, green: 0.84, blue: 0.38)

private func formatTime(_ s: Double) -> String {
    let t = max(0, Int(s))
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct Artwork: View {
    let image: NSImage?
    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Background: View {
    let image: NSImage?
    var body: some View {
        ZStack {
            Color(white: 0.08)
            if let image {
                Image(nsImage: image).resizable().scaledToFill().blur(radius: 40).opacity(0.55)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct Progress: View {
    let state: PlayerState
    var body: some View {
        let start = state.capturedAt.addingTimeInterval(-state.position)
        let end = start.addingTimeInterval(max(state.duration, 1))
        VStack(spacing: 3) {
            Group {
                if state.isPlaying && state.duration > 0 && end > Date() {
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: min(state.position, max(state.duration, 1)), total: max(state.duration, 1))
                }
            }
            .progressViewStyle(.linear)
            .tint(spotifyGreen)

            HStack {
                if state.isPlaying && state.duration > 0 && end > Date() {
                    Text(timerInterval: start...end, countsDown: false)
                } else {
                    Text(formatTime(state.position))
                }
                Spacer()
                Text(formatTime(state.duration))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.65))
        }
    }
}

struct ControlButton: View {
    let symbol: String
    let command: String
    let size: CGFloat
    var body: some View {
        Button(intent: SpotifyCommandIntent(command)) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .frame(width: size + 16, height: size + 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NotRunningView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(spotifyGreen)
            Text("Spotify is closed").font(.headline)
            Button(intent: SpotifyCommandIntent("open")) {
                Text("Open Spotify").font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(spotifyGreen)).foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MediumView: View {
    let entry: Entry
    var body: some View {
        let s = entry.state
        HStack(spacing: 14) {
            Artwork(image: entry.artwork).frame(width: 118, height: 118)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title.isEmpty ? "Nothing playing" : s.title)
                    .font(.system(size: 14, weight: .bold)).lineLimit(2)
                Text(s.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                Spacer(minLength: 6)
                Progress(state: s)
                HStack(spacing: 10) {
                    ControlButton(symbol: "backward.fill", command: "previous", size: 15)
                    ControlButton(symbol: s.isPlaying ? "pause.fill" : "play.fill", command: "playpause", size: 22)
                    ControlButton(symbol: "forward.fill", command: "next", size: 15)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct SmallView: View {
    let entry: Entry
    var body: some View {
        let s = entry.state
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Artwork(image: entry.artwork).frame(width: 64, height: 64)
                Spacer()
                VStack(spacing: 0) {
                    ControlButton(symbol: s.isPlaying ? "pause.fill" : "play.fill", command: "playpause", size: 20)
                    ControlButton(symbol: "forward.fill", command: "next", size: 14)
                }
            }
            Spacer(minLength: 4)
            Text(s.title.isEmpty ? "Nothing playing" : s.title)
                .font(.system(size: 13, weight: .bold)).lineLimit(1)
            Text(s.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                .padding(.bottom, 6)
            Progress(state: s)
        }
    }
}

struct SpotifyWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        Group {
            if !entry.state.running {
                NotRunningView()
            } else if family == .systemSmall {
                SmallView(entry: entry)
            } else {
                MediumView(entry: entry)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { Background(image: entry.artwork) }
        .widgetURL(URL(string: "spotify:"))
    }
}

@main
struct SpotifyNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpotifyNowPlaying", provider: Provider()) { entry in
            SpotifyWidgetView(entry: entry)
        }
        .configurationDisplayName("Spotify")
        .description("See what's playing and control Spotify.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
