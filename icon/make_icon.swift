import Foundation
import CoreGraphics
import ImageIO

// Draws a Spotify-style placeholder icon: a green circle with three white sound-wave arcs.
func makeIcon(size S: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: Int(S), height: Int(S),
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Green circle (transparent corners).
    let inset = S * 0.06
    let circle = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    ctx.setFillColor(CGColor(red: 0.118, green: 0.843, blue: 0.376, alpha: 1)) // #1ED760
    ctx.fillEllipse(in: circle)

    // Three concentric arcs that bulge upward, like radio/sound waves.
    let cx = S * 0.5
    let cyBottom = S * 0.05   // arc centre, near the bottom (y-up coordinates)
    let waves: [(r: CGFloat, half: CGFloat, w: CGFloat)] = [
        (0.61 * S, 58 * .pi / 180, 0.085 * S),
        (0.48 * S, 55 * .pi / 180, 0.070 * S),
        (0.37 * S, 50 * .pi / 180, 0.055 * S),
    ]
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineCap(.round)
    for w in waves {
        ctx.setLineWidth(w.w)
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: cx, y: cyBottom), radius: w.r,
                   startAngle: .pi / 2 - w.half, endAngle: .pi / 2 + w.half, clockwise: false)
        ctx.strokePath()
    }
    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments[1]
let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, s) in sizes {
    writePNG(makeIcon(size: s), to: "\(outDir)/\(name).png")
}
// A standalone 256px copy for the README.
writePNG(makeIcon(size: 256), to: "\(outDir)/../readme_icon.png")
print("wrote iconset to \(outDir)")
