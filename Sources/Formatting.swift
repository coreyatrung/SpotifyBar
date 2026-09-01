import CoreGraphics
import Foundation

enum TimeFormat {
    /// m:ss. Guards NaN, infinity and negatives — all of which are reachable from a
    /// partial read of Spotify, and none of which format sensibly.
    static func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// How far along a horizontal control a point landed, as 0...1. Used by the scrubber.
func fractionAlong(_ x: CGFloat, width: CGFloat) -> Double {
    guard width > 0, x.isFinite else { return 0 }
    return Double(min(max(x / width, 0), 1))
}

/// `value / total`, clamped to 0...1 and NaN-safe.
///
/// Swift's `min`/`max` propagate NaN rather than clamping it, so a NaN duration used
/// to survive all the way into a SwiftUI `frame(width:)` — which is a hard error, not
/// a cosmetic one.
func clampedFraction(_ value: Double, of total: Double) -> Double {
    guard value.isFinite, total.isFinite, total > 0 else { return 0 }
    return min(max(value / total, 0), 1)
}
