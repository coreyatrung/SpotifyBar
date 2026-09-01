import SwiftUI

/// The view that lives in the menu bar: animated equalizer + scrolling ticker + elapsed time.
/// Its overall width is set by AppDelegate (state.menuWidth) so it takes only the space it needs.
struct MenuBarLabel: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        Group {
            if state.isPlaying {
                // One timeline drives both the equalizer and the ticker.
                //
                // They used to run separate TimelineViews. Each one independently forced a
                // full status item redraw, so the menu bar did twice the work for the same
                // animation — and neither was rate-limited, so on a ProMotion display that
                // was 240 status item redraws a second between them.
                TimelineView(.animation(minimumInterval: MenuBarLayout.animationInterval)) { context in
                    content(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Nothing playing: no timeline at all, so the app costs nothing at rest.
                content(time: nil)
            }
        }
        .frame(width: state.menuWidth, height: MenuBarLayout.height)
    }

    /// `time` nil means "not animating" — flat equalizer, static ticker.
    private func content(time: Double?) -> some View {
        HStack(spacing: MenuBarLayout.spacing) {
            if state.isRunning {
                EqualizerIcon(time: time)
            } else {
                Image(systemName: "music.note").font(.system(size: 12))
            }

            if state.isRunning, !state.title.isEmpty {
                MarqueeText(text: Self.ticker(title: state.title, artist: state.artist),
                            window: state.tickerWindow,
                            scrollWidth: state.tickerScrollWidth,
                            time: time)
                    .font(Font(MenuBarLayout.tickerNSFont))
                Text(TimeFormat.mmss(state.position))
                    .font(Font(MenuBarLayout.timeNSFont))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The exact string AppDelegate measures to size the status item. Both sides must
    /// build it the same way, so they both call this.
    static func ticker(title: String, artist: String) -> String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }
}

/// Four bars whose heights wobble on sine waves while music plays; flat when paused/stopped.
/// Driven by the shared clock in MenuBarLabel rather than a timeline of its own.
struct EqualizerIcon: View {
    let time: Double?

    private static let barCount = 4
    private static let barWidth: CGFloat = 2.5
    private static let barSpacing: CGFloat = 2
    private static let minBarHeight: CGFloat = 3
    private static let maxBarHeight: CGFloat = 14
    /// Deliberately unrelated so the bars never fall into a visible shared rhythm.
    private static let speeds: [Double] = [3.0, 4.3, 2.6, 3.7]
    private static let phases: [Double] = [0.0, 1.1, 2.0, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: Self.barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: Self.barWidth, height: height(index))
            }
        }
        .frame(width: MenuBarLayout.equalizerWidth, height: MenuBarLayout.equalizerHeight)
    }

    private func height(_ index: Int) -> CGFloat {
        guard let time else { return Self.minBarHeight }
        let wave = (sin(time * Self.speeds[index] + Self.phases[index]) + 1) / 2   // 0...1
        return Self.minBarHeight + wave * (Self.maxBarHeight - Self.minBarHeight)
    }
}

/// Scrolls text seamlessly (with a "·" separator) if it overflows `window`; otherwise static.
///
/// The widths come in from AppDelegate, which already measures this exact string with this
/// exact font to size the status item. The view used to measure itself with a GeometryReader
/// nested *inside* its animation timeline, so every frame re-laid-out the text and pushed a
/// SwiftUI preference up the tree — at display refresh rate, forever.
struct MarqueeText: View {
    let text: String
    let window: CGFloat
    /// Total scroll distance, i.e. text + separator. Zero means it fits and shouldn't scroll.
    let scrollWidth: CGFloat
    /// Shared clock from MenuBarLabel. Nil means hold still.
    let time: Double?

    var body: some View {
        ZStack(alignment: .leading) {
            if let time, scrollWidth > 0 {
                let speed = MenuBarLayout.tickerScrollSpeed
                let period = Double(scrollWidth / speed)
                let elapsed = time.truncatingRemainder(dividingBy: period)
                HStack(spacing: 0) {
                    Text(text + MenuBarLayout.tickerSeparator)
                    Text(text + MenuBarLayout.tickerSeparator)
                }
                .fixedSize()
                .offset(x: -CGFloat(elapsed) * speed)
            } else {
                Text(text).fixedSize()
            }
        }
        .frame(width: window, height: MenuBarLayout.tickerHeight, alignment: .leading)
        .clipped()
    }
}
