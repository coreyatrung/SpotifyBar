import Foundation

enum PlayerStateValue: String {
    case playing, paused, stopped, unknown
}

/// How the last read of Spotify went.
///
/// This used to be a single `isRunning` flag, so "Spotify isn't open" and "we couldn't
/// read Spotify" were indistinguishable — any failure at all made the app claim Spotify
/// was closed while it was sitting there playing.
enum SpotifyStatus {
    case ok                 // Spotify is running and we read it
    case notRunning         // Spotify isn't running
    case permissionDenied   // macOS Automation access hasn't been granted
    case unreadable         // Spotify is probably running, but the read failed or timed out
}

struct PlayerSnapshot: Equatable {
    var status: SpotifyStatus = .notRunning
    var state: PlayerStateValue = .unknown
    /// Spotify's own id, e.g. `spotify:track:5uCqq6xihfaRNRky8wZVO2`. Used to spot a real
    /// track change — the title alone can't tell a repeat from a pause.
    var trackID = ""
    var title = ""
    var artist = ""
    var album = ""
    var artworkURL = ""
    var position: Double = 0   // seconds
    var duration: Double = 0   // seconds
    var volume: Double = 50    // 0...100

    var isRunning: Bool { status == .ok }
}

/// Talks to the local Spotify desktop app via in-process AppleScript (NSAppleScript).
/// In-process so the macOS Automation permission is attributed to SpotifyBar itself.
///
/// Every script runs on a private serial queue, never on the main thread. NSAppleScript
/// blocks the calling thread until Spotify replies, so doing this on main meant a
/// beachballing Spotify froze SpotifyBar with it — and the very first call, which is
/// what triggers the macOS consent dialog, blocked app launch until the user clicked.
final class SpotifyController {
    /// U+0001, a control character no track title can contain. The old `|~|` delimiter
    /// could appear in a title, and one that did shifted every field after it — artist
    /// became the album, the artwork URL became the artist, and the volume came back
    /// as whatever the duration happened to be.
    static let delimiter = "\u{01}"
    private static let fieldCount = 10

    /// How long to wait on Spotify before giving up. Enforced inside AppleScript, so a
    /// wedged Spotify costs one slow tick rather than a permanently stuck queue.
    private static let scriptTimeout = 5

    /// NSAppleScript is not thread-safe, so all access — reads and commands — is
    /// funnelled through this one serial queue.
    private let queue = DispatchQueue(label: "com.coreyhearne.spotifybar.applescript", qos: .utility)

    private var compiledRead: NSAppleScript?
    private var compiledCommands: [String: NSAppleScript] = [:]

    /// Set to hear about a command that failed because Automation access was revoked
    /// mid-session. Called on the main thread. Command errors used to be dropped
    /// entirely, so the buttons just quietly stopped working.
    var onPermissionDenied: (() -> Void)?

    /// Guards against stacking reads if one tick takes longer than the poll interval.
    /// Main thread only.
    private var readInFlight = false

    // MARK: - Reading

    /// Every property is read inside its own `try`, so one that comes back as
    /// `missing value` — which happens on ads, some local files and some podcast
    /// episodes, where `artwork url` is empty — costs that one field instead of
    /// failing the whole snapshot.
    ///
    /// Times are returned as whole milliseconds rather than coerced reals. AppleScript's
    /// number-to-string coercion uses the system decimal separator, so `1.5` arrives as
    /// `"1,5"` on a European Mac and `Double("1,5")` is nil. Integers have no separator.
    private static let readSource = """
    set d to (character id 1)
    with timeout of \(scriptTimeout) seconds
      if application "Spotify" is running then
        tell application "Spotify"
          set pstate to "unknown"
          try
            set pstate to (player state as string)
          end try
          set vol to "50"
          try
            set vol to ((sound volume) as string)
          end try
          set tid to ""
          set nm to ""
          set ar to ""
          set al to ""
          set au to ""
          set posMS to "0"
          set durMS to "0"
          if pstate is not "stopped" then
            try
              set tid to ((id of current track) as string)
            end try
            try
              set nm to ((name of current track) as string)
            end try
            try
              set ar to ((artist of current track) as string)
            end try
            try
              set al to ((album of current track) as string)
            end try
            try
              set au to ((artwork url of current track) as string)
            end try
            try
              set posMS to ((round ((player position) * 1000)) as string)
            end try
            try
              set durMS to ((duration of current track) as string)
            end try
          end if
          return "ok" & d & pstate & d & tid & d & nm & d & ar & d & al & d & au & d & posMS & d & durMS & d & vol
        end tell
      else
        return "notrunning" & d & "stopped" & d & "" & d & "" & d & "" & d & "" & d & "" & d & "0" & d & "0" & d & "50"
      end if
    end timeout
    """

    /// Reads Spotify on the background queue and delivers the result on the main thread.
    /// Call from the main thread.
    func snapshot(_ completion: @escaping (PlayerSnapshot) -> Void) {
        guard !readInFlight else { return }
        readInFlight = true
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.readSnapshot()
            DispatchQueue.main.async {
                self.readInFlight = false
                completion(snapshot)
            }
        }
    }

    private func readSnapshot() -> PlayerSnapshot {
        if compiledRead == nil { compiledRead = NSAppleScript(source: Self.readSource) }
        guard let script = compiledRead else { return PlayerSnapshot(status: .unreadable) }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return PlayerSnapshot(status: Self.status(forError: error)) }
        return Self.parse(result.stringValue ?? "")
    }

    static func status(forError error: NSDictionary) -> SpotifyStatus {
        switch (error["NSAppleScriptErrorNumber"] as? Int) ?? 0 {
        case -1743: return .permissionDenied            // errAEEventNotPermitted
        case -600, -609: return .notRunning             // procNotFound, connectionInvalid
        default: return .unreadable                     // -1712 timeout, -1700 coercion, anything else
        }
    }

    static func parse(_ raw: String) -> PlayerSnapshot {
        let parts = raw.components(separatedBy: delimiter)
        // Exactly nine fields or we don't trust any of it. The old `>= 9` check let a
        // delimiter in a track title through with everything silently shifted along.
        guard parts.count == fieldCount else { return PlayerSnapshot(status: .unreadable) }
        guard parts[0] == "ok" else { return PlayerSnapshot(status: .notRunning) }

        var snapshot = PlayerSnapshot(status: .ok)
        snapshot.state = PlayerStateValue(rawValue: parts[1]) ?? .unknown
        snapshot.trackID = parts[2]
        snapshot.title = parts[3]
        snapshot.artist = parts[4]
        snapshot.album = parts[5]
        snapshot.artworkURL = parts[6]
        // Spotify's scripting definition describes `duration` as seconds. It has always
        // actually been milliseconds — do not "fix" this division.
        snapshot.position = (Double(parts[7]) ?? 0) / 1000
        snapshot.duration = (Double(parts[8]) ?? 0) / 1000
        snapshot.volume = min(max(Double(parts[9]) ?? 50, 0), 100)
        return snapshot
    }

    // MARK: - Commands

    func playPause() { runCached("playpause") }
    func next()      { runCached("next track") }
    func previous()  { runCached("previous track") }
    func activateSpotify() { runCached("activate") }

    func seek(to seconds: Double) {
        // NaN or infinity would interpolate as `nan` / `inf`, which AppleScript reads as
        // undefined variables and rejects outright (-2753).
        guard seconds.isFinite, seconds >= 0 else { return }
        run(command: "set player position to \(min(seconds, 86_400))", cache: false)
    }

    func setVolume(_ value: Int) {
        run(command: "set sound volume to \(max(0, min(100, value)))", cache: false)
    }

    /// Commands with no varying value get compiled once and reused. Seek and volume
    /// carry a number in the source, so they can't be keyed this way.
    private func runCached(_ command: String) { run(command: command, cache: true) }

    private func run(command: String, cache: Bool) {
        let source = """
        with timeout of \(Self.scriptTimeout) seconds
          tell application "Spotify" to \(command)
        end timeout
        """
        queue.async { [weak self] in
            guard let self else { return }
            let script: NSAppleScript?
            if cache {
                if let cached = self.compiledCommands[source] {
                    script = cached
                } else {
                    script = NSAppleScript(source: source)
                    if let compiled = script { self.compiledCommands[source] = compiled }
                }
            } else {
                script = NSAppleScript(source: source)
            }

            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            guard let error else { return }

            #if DEBUG
            print("[SpotifyController] command failed: \(command) — \(error)")
            #endif
            if Self.status(forError: error) == .permissionDenied {
                DispatchQueue.main.async { self.onPermissionDenied?() }
            }
        }
    }
}
