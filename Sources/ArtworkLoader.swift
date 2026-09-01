import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Fetches the album art once per track and keeps two versions of it: the cover itself,
/// and a small pre-blurred copy for the panel background.
///
/// This replaces two separate `AsyncImage` views pointed at the same URL — one for the
/// cover, one for the background — which meant two decodes per track change, and a
/// 40pt Gaussian blur recomputed on the GPU every frame behind the panel. The blur now
/// happens once, on a 64px thumbnail, per track.
///
/// This is also the app's only outbound network request: the artwork comes from
/// Spotify's image CDN. No account, no credentials, no telemetry.
final class ArtworkLoader: ObservableObject {
    @Published private(set) var cover: NSImage?
    @Published private(set) var background: NSImage?

    private var loadedURL = ""
    private var task: URLSessionDataTask?
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let processing = DispatchQueue(label: "com.coreyhearne.spotifybar.artwork", qos: .utility)

    private static let thumbnailSide: CGFloat = 64
    private static let blurRadius: Float = 8

    /// Call from the main thread. Cheap to call repeatedly — it ignores a URL it has.
    func load(_ urlString: String) {
        guard urlString != loadedURL else { return }
        loadedURL = urlString
        task?.cancel()
        task = nil

        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            cover = nil
            background = nil
            return
        }

        let job = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            self.processing.async {
                let blurred = self.blurredThumbnail(of: image)
                DispatchQueue.main.async {
                    // The track may have moved on while this was in flight.
                    guard self.loadedURL == urlString else { return }
                    self.cover = image
                    self.background = blurred
                }
            }
        }
        task = job
        job.resume()
    }

    /// Downsample hard, then blur once. At 70% opacity under a material layer nobody can
    /// tell it started life as a 64px thumbnail.
    private func blurredThumbnail(of image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let source = CIImage(data: tiff) else { return nil }

        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scale = Self.thumbnailSide / max(extent.width, extent.height)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let filter = CIFilter.gaussianBlur()
        filter.inputImage = small.clampedToExtent()
        filter.radius = Self.blurRadius

        guard let output = filter.outputImage?.cropped(to: small.extent),
              let cgImage = context.createCGImage(output, from: small.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
