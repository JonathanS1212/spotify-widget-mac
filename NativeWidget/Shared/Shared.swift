import Foundation

/// Paths and state shared between the helper app and the widget.
///
/// This is a plain folder in ~/Library/Application Support rather than an App Group container: the app is
/// ad-hoc signed, and macOS 15 won't let the sandboxed widget into an App Group that isn't tied to a signing team.
/// The widget reaches the folder through a sandbox exception in Widget.entitlements.
enum Shared {
    static let container: URL = {
        // Inside the sandbox NSHomeDirectory() points at the widget's container, so look up the real home.
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Spotify Widget")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static var stateURL: URL { container.appendingPathComponent("state.json") }
    static var artworkURL: URL { container.appendingPathComponent("artwork.jpg") }
    static var commandURL: URL { container.appendingPathComponent("command.txt") }
    static let commandNotification = "com.sztjonathan.spotifywidget.command"

    /// Sent from the widget: the helper app picks the command up and forwards it to Spotify.
    static func send(_ command: String) {
        try? command.write(to: commandURL, atomically: true, encoding: .utf8)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(commandNotification as CFString), nil, nil, true)
    }
}

struct PlayerState: Codable, Equatable {
    var running = false
    var isPlaying = false
    var title = ""
    var artist = ""
    var duration: Double = 0      // seconds
    var position: Double = 0      // seconds, at capturedAt
    var capturedAt = Date()
    var artworkSource: String?    // Spotify URL of the image saved at Shared.artworkURL

    /// Playback position extrapolated to `date`.
    func position(at date: Date) -> Double {
        isPlaying ? min(duration, position + date.timeIntervalSince(capturedAt)) : position
    }

    static func load() -> PlayerState {
        guard let data = try? Data(contentsOf: Shared.stateURL),
              let s = try? JSONDecoder().decode(PlayerState.self, from: data) else { return PlayerState() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Shared.stateURL, options: .atomic) }
    }
}
