import SwiftUI

/// The view that lives in the menu bar: animated equalizer + scrolling ticker + elapsed time.
/// Its overall width is set by AppDelegate (state.menuWidth) so it takes only the space it needs.
struct MenuBarLabel: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        HStack(spacing: 6) {
            if state.isRunning {
                EqualizerIcon(active: state.isPlaying)
            } else {
                Image(systemName: "music.note").font(.system(size: 12))
            }

            if state.isRunning, !state.title.isEmpty {
                MarqueeText(text: "\(state.title) — \(state.artist)", window: state.tickerWindow)
                    .font(.system(size: 12, weight: .medium))
                Text(Self.fmt(state.position))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: state.menuWidth, height: 22)
    }

    static func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Four bars whose heights wobble on sine waves while music plays; flat when paused/stopped.
struct EqualizerIcon: View {
    let active: Bool
    private let speeds: [Double] = [3.0, 4.3, 2.6, 3.7]
    private let phases: [Double] = [0.0, 1.1, 2.0, 0.5]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2.5, height: height(i, t))
                }
            }
            .frame(width: 18, height: 14)
        }
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        guard active else { return 3 }
        let v = (sin(t * speeds[i] + phases[i]) + 1) / 2   // 0...1
        return 3 + v * 11
    }
}

/// Scrolls text seamlessly (with a "·" separator) if it overflows `window`; otherwise static.
struct MarqueeText: View {
    let text: String
    let window: CGFloat
    @State private var contentWidth: CGFloat = 0

    private let speed: CGFloat = 30      // points per second
    private let separator = "   ·   "

    var body: some View {
        let full = text + separator
        let needsScroll = contentWidth > window + 1
        ZStack(alignment: .leading) {
            if needsScroll {
                TimelineView(.animation) { ctx in
                    let period = Double(contentWidth / speed)
                    let elapsed = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                    let offset = -CGFloat(elapsed) * speed
                    HStack(spacing: 0) {
                        measured(full)
                        Text(full)
                    }
                    .fixedSize()
                    .offset(x: offset)
                }
            } else {
                measured(text)
            }
        }
        .frame(width: window, height: 16, alignment: .leading)
        .clipped()
        .onPreferenceChange(TextWidthKey.self) { contentWidth = $0 }
    }

    private func measured(_ s: String) -> some View {
        Text(s)
            .fixedSize()
            .background(GeometryReader { g in
                Color.clear.preference(key: TextWidthKey.self, value: g.size.width)
            })
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
