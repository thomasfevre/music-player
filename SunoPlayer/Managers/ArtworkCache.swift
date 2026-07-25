import UIKit

/// UIKit does not declare `UIImage` Sendable, although this wrapper is only used to hand an
/// immutable decoded image from a background task back to the main actor.
private struct DecodedArtwork: @unchecked Sendable {
    let image: UIImage
}

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
        guard let track else {
            image = nil
            loadedKey = nil
            return
        }
        load(fileName: track.preferredArtworkFileName, url: track.artworkURL)
    }

    /// Loads any artwork file using the same background decoder and shared cache.
    func load(fileName: String?, url: URL?) {
        guard let fileName, let url else {
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
        Task { @MainActor [weak self] in
            let decoded = await Task.detached(priority: .utility) { () -> DecodedArtwork? in
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else { return nil }
                return DecodedArtwork(image: image)
            }.value
            guard let decoded else { return }

            // Keep every cache access on the main actor. Besides making NSCache use consistent,
            // this avoids a Swift 6 isolation error from the background decode task.
            Self.cache.setObject(decoded.image, forKey: key)
            guard self?.loadedKey == fileName else { return }
            self?.image = decoded.image
        }
    }

    /// Drops a track's image from the shared cache (call when its file is deleted or replaced).
    static func remove(_ track: Track) {
        [track.artworkFileName, track.customArtworkFileName]
            .compactMap { $0 }
            .forEach { cache.removeObject(forKey: $0 as NSString) }
    }

    /// Drops a cache entry by its raw artwork file name (used before overwriting on re-import).
    static func remove(byKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
