import AppKit

/// Shared geometry and fonts for the menu bar item.
///
/// AppDelegate measures text against these to size the status item, and MenuBarLabel
/// lays out inside the same numbers. They used to be duplicated on both sides — the
/// padding chain lived as a bare `6 + 18 + 6 + …` sum in AppDelegate while the spacing
/// lived in an HStack in the view, so the two could drift apart without anyone noticing.
enum MenuBarLayout {
    static let height: CGFloat = 22
    static let spacing: CGFloat = 6           // gap between equalizer, ticker and time
    static let inset: CGFloat = 6             // leading and trailing padding
    static let equalizerWidth: CGFloat = 18
    static let equalizerHeight: CGFloat = 14
    static let tickerHeight: CGFloat = 16
    static let maxTickerWidth: CGFloat = 150  // cap so a long title can't eat the menu bar
    static let idleWidth: CGFloat = 30        // just the music note, nothing playing

    /// Marquee. The separator is what makes the loop look seamless when the text wraps
    /// around, so its width counts towards the scroll distance.
    static let tickerSeparator = "   ·   "
    static let tickerScrollSpeed: CGFloat = 30          // points per second
    /// One interval for the whole label, because one redraw covers both animations.
    ///
    /// Updating a status item is expensive on macOS — measured at roughly 1% of a core
    /// per update-per-second, and that holds whether the drawing is SwiftUI or raw Core
    /// Graphics. So the frame rate *is* the CPU budget. At 30pt/s the ticker moves about
    /// 2.5pt per frame here, which reads as smooth in a menu bar.
    static let animationInterval: Double = 1.0 / 12.0

    /// Measured and rendered with the same font objects, so the status item can't
    /// end up a few points wider or narrower than the text it holds.
    static let tickerNSFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    /// Monospaced digits so the measured width doesn't change as the seconds tick —
    /// otherwise the whole item wobbles once a second.
    static let timeNSFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// inset + equalizer + gap + ticker + gap + time + inset
    static func totalWidth(ticker: CGFloat, time: CGFloat) -> CGFloat {
        inset + equalizerWidth + spacing + ticker + spacing + time + inset
    }
}

/// Geometry for the now-playing popover. The permission prompt is much shorter than
/// the player, and the popover is pinned to a fixed size, so it gets its own height.
enum PanelLayout {
    static let width: CGFloat = 280
    static let playerHeight: CGFloat = 460
    static let permissionHeight: CGFloat = 250
    static let artworkSide: CGFloat = 220
    static let padding: CGFloat = 16
}

/// Geometry and timing for the track-change toast that drops out of the menu bar.
enum ToastLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 76
    static let artworkSide: CGFloat = 52
    static let padding: CGFloat = 12
    static let cornerRadius: CGFloat = 12

    /// How far the card travels on its way in. The panel is this much taller than the card
    /// so the travel happens inside the window rather than by moving the window.
    static let slide: CGFloat = 14
    static let menuBarGap: CGFloat = 6
    static let screenMargin: CGFloat = 8
    /// Slack around the card inside the panel so its drop shadow isn't clipped at the
    /// window edge.
    static let shadowMargin: CGFloat = 18

    static var panelWidth: CGFloat { width + shadowMargin * 2 }
    static var panelHeight: CGFloat { height + slide + shadowMargin }

    static let hold: TimeInterval = 4          // visible time before it starts to fade
    static let transition: TimeInterval = 0.25
}
