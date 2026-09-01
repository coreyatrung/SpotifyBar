import SwiftUI

/// Observable snapshot of what Spotify is doing right now. Drives the SwiftUI views.
final class PlayerState: ObservableObject {
    @Published private(set) var status: SpotifyStatus = .notRunning
    @Published private(set) var stateValue: PlayerStateValue = .unknown
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artworkURL = ""
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var volume: Double = 50

    // Menu bar layout, computed by AppDelegate from measured text widths.
    @Published private(set) var tickerWindow: CGFloat = 0
    /// Scroll distance for the marquee (text + separator), or 0 if the title fits.
    @Published private(set) var tickerScrollWidth: CGFloat = 0
    @Published private(set) var menuWidth: CGFloat = MenuBarLayout.idleWidth

    var isRunning: Bool { status == .ok }
    var isPlaying: Bool { stateValue == .playing }
    var permissionDenied: Bool { status == .permissionDenied }

    /// After a command is sent, Spotify takes a moment to catch up. A poll landing in
    /// that window reports the old value and snaps the control backwards. Holding the
    /// field for slightly longer than one poll interval stops that.
    ///
    /// The scrubber used to do this with a 0.5s `asyncAfter` — shorter than the 1s poll,
    /// so it didn't reliably work — and the volume slider didn't do it at all.
    private static let commandHold: TimeInterval = 1.5
    private var positionHeldUntil = Date.distantPast
    private var volumeHeldUntil = Date.distantPast

    /// The last snapshot applied in full, used to skip no-op updates.
    private var lastApplied: PlayerSnapshot?

    func apply(_ snapshot: PlayerSnapshot) {
        let now = Date()
        let holdingPosition = now < positionHeldUntil
        let holdingVolume = now < volumeHeldUntil

        // Only take the early exit when nothing is held back. Otherwise a held field
        // could never catch up: the snapshot would compare equal forever and the stale
        // value would stick after the hold expired.
        if !holdingPosition, !holdingVolume, snapshot == lastApplied { return }
        lastApplied = (holdingPosition || holdingVolume) ? nil : snapshot

        // Assign only what changed. Every @Published write fires objectWillChange, so
        // blanket-assigning all nine fields invalidated the popover and the menu bar
        // label nine times a second even with Spotify paused and nothing happening.
        if status != snapshot.status { status = snapshot.status }
        if stateValue != snapshot.state { stateValue = snapshot.state }
        if title != snapshot.title { title = snapshot.title }
        if artist != snapshot.artist { artist = snapshot.artist }
        if album != snapshot.album { album = snapshot.album }
        if artworkURL != snapshot.artworkURL { artworkURL = snapshot.artworkURL }
        if duration != snapshot.duration { duration = snapshot.duration }
        if !holdingPosition, position != snapshot.position { position = snapshot.position }
        if !holdingVolume, volume != snapshot.volume { volume = snapshot.volume }
    }

    /// Show the seeked-to position immediately and ignore polled positions until
    /// Spotify has had time to apply it.
    func holdPosition(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = seconds
        positionHeldUntil = Date().addingTimeInterval(Self.commandHold)
    }

    /// Same, for the volume slider.
    func holdVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = value
        volumeHeldUntil = Date().addingTimeInterval(Self.commandHold)
    }

    /// Flip the play/pause icon straight away rather than waiting for the next poll.
    /// The following poll corrects it if the command didn't land.
    func optimisticallyTogglePlayback() {
        stateValue = isPlaying ? .paused : .playing
    }

    func setMenuLayout(tickerWindow: CGFloat, scrollWidth: CGFloat, width: CGFloat) {
        if self.tickerWindow != tickerWindow { self.tickerWindow = tickerWindow }
        if tickerScrollWidth != scrollWidth { tickerScrollWidth = scrollWidth }
        if menuWidth != width { menuWidth = width }
    }
}
