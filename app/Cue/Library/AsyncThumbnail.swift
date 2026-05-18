import SwiftUI
import CoreGraphics

/// Process-wide decoded-image cache. Keyed by "filename@maxPixel" so the same
/// file at different sizes (grid 400 / filmstrip 160 / pager 2000) cache
/// independently. NSCache auto-evicts under memory pressure.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, CGImage>()
    private init() { cache.countLimit = 120 }

    func image(for key: String) -> CGImage? { cache.object(forKey: key as NSString) }
    func set(_ image: CGImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

/// A thumbnail that decodes OFF the main thread and caches the result.
///
/// The library views previously decoded JPEGs synchronously inside `body`,
/// so every SwiftUI re-render (and a paged TabView re-renders constantly
/// while swiping) re-decoded a multi-MP image on the main thread — janky.
/// This view decodes once on a background task, caches it, and renders the
/// cached CGImage instantly on every subsequent render.
struct AsyncThumbnail: View {
    let store: LibraryStore
    let filename: String
    let maxPixel: CGFloat
    var contentMode: ContentMode = .fill

    @State private var image: CGImage?

    private var cacheKey: String { "\(filename)@\(Int(maxPixel))" }

    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: filename) {
            if let cached = ImageCache.shared.image(for: cacheKey) {
                image = cached
                return
            }
            let key = cacheKey
            let name = filename
            let px = maxPixel
            let s = store
            let decoded = await Task.detached(priority: .userInitiated) {
                s.loadThumbnail(name, maxPixel: px)
            }.value
            guard !Task.isCancelled else { return }
            if let decoded {
                ImageCache.shared.set(decoded, for: key)
            }
            image = decoded
        }
    }
}
