import SwiftUI

/// Observable snapshot of what Spotify is doing right now. Drives the SwiftUI views.
final class PlayerState: ObservableObject {
    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published var stateValue: PlayerStateValue = .unknown
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var artworkURL = ""
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 50

    // Menu bar layout, computed by AppDelegate from measured text widths.
    @Published var tickerWindow: CGFloat = 0   // px allotted to the scrolling title
    @Published var menuWidth: CGFloat = 30      // total px width of the menu bar label

    var isPlaying: Bool { stateValue == .playing }

    func apply(_ s: PlayerSnapshot) {
        isRunning = s.isRunning
        permissionDenied = s.permissionDenied
        stateValue = s.state
        title = s.title
        artist = s.artist
        album = s.album
        if artworkURL != s.artworkURL { artworkURL = s.artworkURL }
        position = s.position
        duration = s.duration
        volume = s.volume
    }
}
