import UIKit

// MARK: - ArtworkLoader
/// Loads extracted cover-art images off the main thread and publishes them back on it,
/// so list rows never block the scroll on synchronous disk I/O. Decoded images are kept in a
/// shared NSCache (auto-evicts under memory pressure) so warm reads are instant.
@MainActor
final class ArtworkLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()
    private var loadedKey: String?

    /// Loads the cover art for a track. Cached images resolve synchronously; cold reads happen
    /// on a background task and update `image` when ready. No-op if the same track is already loaded.
    func load(for track: Track?) {
        guard let track, let fileName = track.artworkFileName, let url = track.artworkURL else {
            image = nil
            loadedKey = nil
            return
        }
        if loadedKey == fileName, image != nil { return }
        loadedKey = fileName

        let key = fileName as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }
        image = nil
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), let loaded = UIImage(data: data) else { return }
            Self.cache.setObject(loaded, forKey: key)
            await MainActor.run { [weak self] in
                // Ignore if the track changed while we were decoding.
                guard self?.loadedKey == fileName else { return }
                self?.image = loaded
            }
        }
    }

    /// Drops a track's image from the shared cache (call when its file is deleted or replaced).
    static func remove(_ track: Track) {
        guard let fileName = track.artworkFileName else { return }
        cache.removeObject(forKey: fileName as NSString)
    }

    /// Drops a cache entry by its raw artwork file name (used before overwriting on re-import).
    static func remove(byKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
