// Tests for the pure logic: time formatting, scrubber maths, and the AppleScript
// response parser. No Spotify, no UI, no Xcode — run them with ./test.sh.

import Foundation

var failures = 0
var checks = 0

func check(_ passed: Bool, _ label: String) {
    checks += 1
    if passed {
        print("  ok    \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)")
    }
}

func group(_ name: String) { print("\n\(name)") }

let d = SpotifyController.delimiter

func response(status: String = "ok",
              state: String = "playing",
              trackID: String = "spotify:track:5uCqq6xihfaRNRky8wZVO2",
              title: String = "Title",
              artist: String = "Artist",
              album: String = "Album",
              artwork: String = "https://i.scdn.co/image/abc",
              positionMS: String = "30000",
              durationMS: String = "210000",
              volume: String = "70") -> String {
    [status, state, trackID, title, artist, album, artwork, positionMS, durationMS, volume]
        .joined(separator: d)
}

// MARK: - TimeFormat

group("TimeFormat.mmss")
check(TimeFormat.mmss(0) == "0:00", "zero")
check(TimeFormat.mmss(9) == "0:09", "pads seconds")
check(TimeFormat.mmss(59) == "0:59", "just under a minute")
check(TimeFormat.mmss(60) == "1:00", "exactly a minute")
check(TimeFormat.mmss(212) == "3:32", "typical track")
check(TimeFormat.mmss(3661) == "61:01", "over an hour keeps counting minutes")
check(TimeFormat.mmss(59.9) == "0:59", "truncates rather than rounds")
check(TimeFormat.mmss(-5) == "0:00", "negative")
check(TimeFormat.mmss(.nan) == "0:00", "NaN")
check(TimeFormat.mmss(.infinity) == "0:00", "infinity")

// MARK: - fractionAlong

group("fractionAlong")
check(fractionAlong(0, width: 100) == 0, "left edge")
check(fractionAlong(50, width: 100) == 0.5, "midpoint")
check(fractionAlong(100, width: 100) == 1, "right edge")
check(fractionAlong(-20, width: 100) == 0, "dragged left of the control")
check(fractionAlong(500, width: 100) == 1, "dragged right of the control")
check(fractionAlong(50, width: 0) == 0, "zero width doesn't divide by zero")
check(fractionAlong(.nan, width: 100) == 0, "NaN location")

// MARK: - clampedFraction

group("clampedFraction")
check(clampedFraction(30, of: 120) == 0.25, "quarter way")
check(clampedFraction(0, of: 120) == 0, "start")
check(clampedFraction(200, of: 120) == 1, "past the end clamps")
check(clampedFraction(-10, of: 120) == 0, "before the start clamps")
check(clampedFraction(30, of: 0) == 0, "zero duration")
check(clampedFraction(.nan, of: 120) == 0, "NaN value can't reach a SwiftUI frame")
check(clampedFraction(30, of: .nan) == 0, "NaN total can't reach a SwiftUI frame")
check(clampedFraction(30, of: .infinity) == 0, "infinite total")

// MARK: - parse

group("SpotifyController.parse — happy path")
let ok = SpotifyController.parse(response())
check(ok.status == .ok, "status ok")
check(ok.state == .playing, "player state")
check(ok.trackID == "spotify:track:5uCqq6xihfaRNRky8wZVO2", "track id")
check(ok.title == "Title", "title")
check(ok.artist == "Artist", "artist")
check(ok.album == "Album", "album")
check(ok.artworkURL == "https://i.scdn.co/image/abc", "artwork url")
check(ok.position == 30, "position converted from milliseconds")
check(ok.duration == 210, "duration converted from milliseconds")
check(ok.volume == 70, "volume")
check(ok.isRunning, "isRunning")

group("SpotifyController.parse — Spotify closed")
let closed = SpotifyController.parse(response(status: "notrunning", state: "stopped"))
check(closed.status == .notRunning, "reported as not running")
check(!closed.isRunning, "isRunning false")

group("SpotifyController.parse — malformed input")
check(SpotifyController.parse("").status == .unreadable, "empty string")
check(SpotifyController.parse("garbage").status == .unreadable, "no delimiters")
check(SpotifyController.parse("ok\(d)playing\(d)Title").status == .unreadable, "too few fields")
// The old parser used `>= 9`, so a delimiter inside a title shifted every field after it
// and was accepted as valid.
check(SpotifyController.parse(response(title: "Odd\(d)Title")).status == .unreadable,
      "too many fields rejected rather than silently shifted")

group("SpotifyController.parse — tolerates partial reads")
let partial = SpotifyController.parse(response(title: "Local File", artist: "", album: "", artwork: ""))
check(partial.status == .ok, "an empty artwork url is still a good read")
check(partial.title == "Local File", "title survives")
check(partial.artworkURL.isEmpty, "artwork url empty")

group("SpotifyController.parse — track identity")
check(SpotifyController.parse(response(trackID: "spotify:track:AAA")).trackID
        != SpotifyController.parse(response(trackID: "spotify:track:BBB")).trackID,
      "different ids are distinguishable")
check(SpotifyController.parse(response(trackID: "spotify:track:AAA", title: "Same Song")).trackID
        == SpotifyController.parse(response(trackID: "spotify:track:AAA", title: "Same Song")).trackID,
      "the same track on repeat has a stable id")
check(SpotifyController.parse(response(trackID: "")).trackID.isEmpty,
      "an empty id is tolerated, not a failed read")
check(SpotifyController.parse(response(trackID: "")).status == .ok,
      "an empty id still parses as a good read")

group("SpotifyController.parse — defensive values")
check(SpotifyController.parse(response(state: "nonsense")).state == .unknown, "unknown player state")
check(SpotifyController.parse(response(positionMS: "abc")).position == 0, "unparseable position")
check(SpotifyController.parse(response(volume: "200")).volume == 100, "volume clamped high")
check(SpotifyController.parse(response(volume: "-40")).volume == 0, "volume clamped low")
check(SpotifyController.parse(response(volume: "x")).volume == 50, "unparseable volume falls back")
check(SpotifyController.parse(response(title: "Song — with punctuation & symbols")).title
        == "Song — with punctuation & symbols", "unicode and ampersands survive")

group("SpotifyController.status(forError:)")
check(SpotifyController.status(forError: ["NSAppleScriptErrorNumber": -1743]) == .permissionDenied,
      "-1743 is a permission problem")
check(SpotifyController.status(forError: ["NSAppleScriptErrorNumber": -600]) == .notRunning,
      "-600 means Spotify isn't there")
check(SpotifyController.status(forError: ["NSAppleScriptErrorNumber": -1712]) == .unreadable,
      "-1712 timeout is unreadable, not closed")
check(SpotifyController.status(forError: ["NSAppleScriptErrorNumber": -1700]) == .unreadable,
      "-1700 coercion failure is unreadable, not closed")
check(SpotifyController.status(forError: [:]) == .unreadable, "missing error number")

// MARK: - TrackChangeDetector

func snap(_ id: String, position: Double = 10, duration: Double = 200,
          status: SpotifyStatus = .ok, state: PlayerStateValue = .playing) -> PlayerSnapshot {
    var s = PlayerSnapshot(status: status)
    s.state = state
    s.trackID = id
    s.title = "Title \(id)"
    s.position = position
    s.duration = duration
    return s
}

group("TrackChangeDetector — launch and steady state")
var det = TrackChangeDetector()
check(det.shouldAnnounce(snap("A")) == false, "never announces the first read after launch")
check(det.shouldAnnounce(snap("A", position: 11)) == false, "same track, time ticking on")
check(det.shouldAnnounce(snap("A", position: 12)) == false, "still the same track")

group("TrackChangeDetector — real changes")
check(det.shouldAnnounce(snap("B")) == true, "a different track announces")
check(det.shouldAnnounce(snap("B", position: 11)) == false, "but only once")
check(det.shouldAnnounce(snap("C")) == true, "and again on the next change")

group("TrackChangeDetector — things that must stay quiet")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A", position: 50))
check(det.shouldAnnounce(snap("A", position: 50, state: .paused)) == false, "pausing")
check(det.shouldAnnounce(snap("A", position: 50, state: .playing)) == false, "resuming")
check(det.shouldAnnounce(snap("A", position: 120)) == false, "seeking forward")
check(det.shouldAnnounce(snap("A", position: 20)) == false, "seeking backward from the middle")
check(det.shouldAnnounce(snap("A", position: 100)) == false, "seeking forward again")

group("TrackChangeDetector — single-track loop")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A", position: 10))
_ = det.shouldAnnounce(snap("A", position: 195))                      // near the end of a 200s track
check(det.shouldAnnounce(snap("A", position: 1)) == true, "wrapping from the end to the start is a loop")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A", position: 100))
check(det.shouldAnnounce(snap("A", position: 1)) == false, "rewinding from the middle is not a loop")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A", position: 195))
check(det.shouldAnnounce(snap("A", position: 40)) == false, "end to mid-track is not a loop")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A", position: 195, duration: 0))
check(det.shouldAnnounce(snap("A", position: 1, duration: 0)) == false, "unknown duration can't be a loop")

group("TrackChangeDetector — Spotify going away")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A"))
check(det.shouldAnnounce(snap("", status: .notRunning)) == false, "quitting Spotify is silent")
check(det.shouldAnnounce(snap("B")) == false, "and reopening it doesn't announce what's loaded")
check(det.shouldAnnounce(snap("C")) == true, "the next genuine change does announce")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A"))
check(det.shouldAnnounce(snap("A", status: .unreadable)) == false, "a failed read is silent")
check(det.shouldAnnounce(snap("A")) == false, "and doesn't announce on recovery")
det = TrackChangeDetector()
_ = det.shouldAnnounce(snap("A"))
check(det.shouldAnnounce(snap("", state: .stopped)) == false, "stopping is silent")

// MARK: - Result

print("\n\(checks - failures)/\(checks) passed")
if failures > 0 {
    print("\(failures) failed")
    exit(1)
}
print("✓ All tests passed")
