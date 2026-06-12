import Foundation

enum PlayerStateValue: String {
    case playing, paused, stopped, unknown
}

struct PlayerSnapshot {
    var isRunning = false
    var permissionDenied = false
    var state: PlayerStateValue = .unknown
    var title = ""
    var artist = ""
    var album = ""
    var artworkURL = ""
    var position: Double = 0   // seconds
    var duration: Double = 0   // seconds
    var volume: Double = 50    // 0...100
}

/// Talks to the local Spotify desktop app via in-process AppleScript (NSAppleScript).
/// In-process so the macOS Automation permission is attributed to SpotifyBar itself.
/// All calls run on the main thread — the scripts are tiny and return in a few ms.
final class SpotifyController {
    private let delim = "|~|"
    private var compiledRead: NSAppleScript?

    private lazy var readSource = """
    if application "Spotify" is running then
      tell application "Spotify"
        set pstate to player state as string
        if pstate is "stopped" then
          return "running\(delim)stopped\(delim)\(delim)\(delim)\(delim)\(delim)0\(delim)0\(delim)0"
        end if
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set artURL to artwork url of current track
        set posSecs to player position
        set durSecs to (duration of current track) / 1000
        set vol to sound volume
        return "running\(delim)" & pstate & "\(delim)" & trackName & "\(delim)" & trackArtist & "\(delim)" & trackAlbum & "\(delim)" & artURL & "\(delim)" & posSecs & "\(delim)" & durSecs & "\(delim)" & vol
      end tell
    else
      return "notrunning\(delim)stopped\(delim)\(delim)\(delim)\(delim)\(delim)0\(delim)0\(delim)0"
    end if
    """

    func currentSnapshot() -> PlayerSnapshot {
        if compiledRead == nil { compiledRead = NSAppleScript(source: readSource) }
        guard let script = compiledRead else { return PlayerSnapshot() }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            var snap = PlayerSnapshot()
            let code = (error["NSAppleScriptErrorNumber"] as? Int) ?? 0
            // -1743 = errAEEventNotPermitted (user hasn't granted Automation access)
            if code == -1743 { snap.permissionDenied = true }
            return snap
        }
        return parse(result.stringValue ?? "")
    }

    func playPause() { runCommand("tell application \"Spotify\" to playpause") }
    func next()      { runCommand("tell application \"Spotify\" to next track") }
    func previous()  { runCommand("tell application \"Spotify\" to previous track") }
    func seek(to seconds: Double) { runCommand("tell application \"Spotify\" to set player position to \(seconds)") }
    func setVolume(_ v: Int) { runCommand("tell application \"Spotify\" to set sound volume to \(max(0, min(100, v)))") }
    func activateSpotify() { runCommand("tell application \"Spotify\" to activate") }

    private func runCommand(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private func parse(_ raw: String) -> PlayerSnapshot {
        var snap = PlayerSnapshot()
        let parts = raw.components(separatedBy: delim)
        guard parts.count >= 9 else { return snap }
        snap.isRunning = parts[0] == "running"
        snap.state = PlayerStateValue(rawValue: parts[1]) ?? .unknown
        snap.title = parts[2]
        snap.artist = parts[3]
        snap.album = parts[4]
        snap.artworkURL = parts[5]
        snap.position = Double(parts[6]) ?? 0
        snap.duration = Double(parts[7]) ?? 0
        snap.volume = Double(parts[8]) ?? 50
        return snap
    }
}
