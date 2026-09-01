import Foundation

/// Decides whether a poll represents a genuine track change worth announcing.
///
/// Kept separate from AppDelegate, and free of AppKit, so the rules are unit-testable —
/// this is the part most likely to misfire, and every misfire is a popup the user didn't ask
/// for.
///
/// The rules:
/// - Never announce the first successful read. On launch there's nothing to compare against,
///   and announcing whatever happens to be loaded is noise.
/// - A different track id is a change. Titles aren't enough: a live and a studio cut of the
///   same song share a title, and pause/resume/seek all leave the title alone.
/// - The same id repeating is only a change when playback wrapped from the very end back to
///   the very beginning, which is what a single-track loop looks like. Scrubbing backwards
///   from the middle deliberately doesn't count.
/// - Spotify quitting, stopping, or failing to read drops the baseline, so bringing it back
///   doesn't announce whatever track is sitting there.
struct TrackChangeDetector {
    /// How near the end the previous poll must have been for a wrap to read as a loop.
    static let endFraction = 0.85
    /// How near the start the new poll must be, in seconds.
    static let startWindow: Double = 3

    private var lastID: String?
    private var lastPosition: Double = 0
    private var hasBaseline = false

    mutating func shouldAnnounce(_ snapshot: PlayerSnapshot) -> Bool {
        guard snapshot.status == .ok, !snapshot.trackID.isEmpty else {
            reset()
            return false
        }

        defer {
            lastID = snapshot.trackID
            lastPosition = snapshot.position
            hasBaseline = true
        }

        guard hasBaseline else { return false }
        if snapshot.trackID != lastID { return true }

        guard snapshot.duration > 0 else { return false }
        let wasAtEnd = lastPosition >= snapshot.duration * Self.endFraction
        let isAtStart = snapshot.position <= Self.startWindow
        return wasAtEnd && isAtStart
    }

    mutating func reset() {
        lastID = nil
        lastPosition = 0
        hasBaseline = false
    }
}
