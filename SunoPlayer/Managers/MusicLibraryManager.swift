import Foundation
import AVFoundation
import Combine

// MARK: - MusicLibraryManager
/// Manages the local track library: importing, persisting, sorting, and searching tracks.
@MainActor
final class MusicLibraryManager: ObservableObject {

    // MARK: Published State
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isImporting: Bool = false
    @Published var sortOrder: SortOrder = .newest
    @Published var searchText: String = ""
    @Published var showFavoritesOnly: Bool = false
    @Published private(set) var favoriteIDs: Set<UUID> = []
    @Published private(set) var lastError: String?

    // MARK: Persistence
    private let saveFileName = "library.json"
    private let favoritesKey = "favoriteTrackIDs"
    private var saveURL: URL {
        Track.documentsDirectory.appendingPathComponent(saveFileName)
    }

    // MARK: Init
    init() {
        loadLibrary()
        loadFavorites()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED") {
            seedDemoLibrary()
        } else {
            refreshMissingMetadata()
        }
        #else
        refreshMissingMetadata()
        #endif
    }

    #if DEBUG
    /// Populates a demo library for App Store screenshot capture (DEBUG only, launch-arg gated).
    /// The first track gets a real silent file so playback / now-playing renders.
    func seedDemoLibrary() {
        let meta: [(String, String, String, String, TimeInterval)] = [
            ("Midnight Drive", "NEON", "Night Signals", "Synthwave", 210),
            ("Velvet Sky", "Aurora Keys", "Night Signals", "Synthwave", 184),
            ("Coastline", "The Tides", "Salt Air", "Indie", 232),
            ("Paper Planes", "Lo-Fi Club", "Study Sessions", "Lo-Fi", 167),
            ("Golden Hour", "Sundara", "Sunset", "Ambient", 198),
            ("Echoes", "Mono Lake", "Reflections", "Ambient", 245),
        ]
        var demo: [Track] = []
        for (i, m) in meta.enumerated() {
            let fileName = "demo-\(i).wav"
            if i == 0 {
                try? Self.silentWAV(seconds: m.4).write(to: Track.documentsDirectory.appendingPathComponent(fileName))
            }
            var track = Track(title: m.0, artist: m.1, album: m.2, genre: m.3,
                              fileName: fileName, duration: m.4,
                              dateImported: Date().addingTimeInterval(Double(-i) * 3600))
            ArtworkPreferences.apply(to: &track)
            demo.append(track)
        }
        tracks = demo
    }

    private static func silentWAV(seconds: Double, sampleRate: Int = 8000) -> Data {
        let bytesPerSample = 2
        let dataSize = Int(seconds * Double(sampleRate)) * bytesPerSample
        var d = Data()
        func s(_ x: String) { d.append(x.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        s("RIFF"); u32(UInt32(36 + dataSize)); s("WAVE"); s("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * bytesPerSample)); u16(UInt16(bytesPerSample)); u16(16)
        s("data"); u32(UInt32(dataSize)); d.append(Data(count: dataSize))
        return d
    }
    #endif

    // MARK: - Computed: Filtered & Sorted Tracks
    var displayedTracks: [Track] {
        TrackQuery.apply(
            tracks: tracks,
            searchText: searchText,
            sortOrder: sortOrder,
            favoriteIDs: showFavoritesOnly ? favoriteIDs : nil
        )
    }

    // MARK: - Favorites
    func isFavorite(_ track: Track) -> Bool {
        favoriteIDs.contains(track.id)
    }

    @discardableResult
    func toggleFavorite(_ track: Track) -> Bool {
        if favoriteIDs.contains(track.id) {
            favoriteIDs.remove(track.id)
        } else {
            favoriteIDs.insert(track.id)
        }
        saveFavorites()
        return favoriteIDs.contains(track.id)
    }

    // MARK: - Artwork

    /// Stores a user-selected image without replacing cover art embedded in the audio file.
    @discardableResult
    func setCustomArtwork(_ data: Data, for track: Track) async -> Bool {
        guard tracks.contains(where: { $0.id == track.id }) else { return false }
        let fileName = "track-\(track.id.uuidString)-\(UUID().uuidString).jpg"
        do {
            try await Task.detached(priority: .userInitiated) {
                try ArtworkStorage.saveImage(
                    data,
                    fileName: fileName,
                    directory: Track.artworkDirectory
                )
            }.value
            guard let index = tracks.firstIndex(where: { $0.id == track.id }) else {
                await Task.detached {
                    ArtworkStorage.removeIfPresent(
                        Track.artworkDirectory.appendingPathComponent(fileName)
                    )
                }.value
                return false
            }
            let previous = tracks[index]
            tracks[index].customArtworkFileName = fileName
            tracks[index].usesGeneratedArtwork = false
            tracks[index].artworkStyle = .photo
            guard saveLibrary() else {
                tracks[index] = previous
                await Task.detached {
                    ArtworkStorage.removeIfPresent(
                        Track.artworkDirectory.appendingPathComponent(fileName)
                    )
                }.value
                return false
            }
            if let previousKey = previous.customArtworkFileName {
                ArtworkLoader.remove(byKey: previousKey)
            }
            await Task.detached {
                ArtworkStorage.removeIfPresent(previous.customArtworkURL)
            }.value
            return true
        } catch {
            lastError = "The artwork for \(track.title) could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    /// Selects a generated color style. A custom photo is removed so the chosen colors are visible.
    @discardableResult
    func setArtworkTheme(_ theme: ArtworkTheme, for track: Track) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return false }
        let previous = tracks[index]
        tracks[index].customArtworkFileName = nil
        tracks[index].usesGeneratedArtwork = true
        tracks[index].artworkStyle = .color
        tracks[index].gradientHue1 = theme.hue1
        tracks[index].gradientHue2 = theme.hue2
        guard saveLibrary() else {
            tracks[index] = previous
            return false
        }
        removeCustomArtworkFile(for: previous)
        return true
    }

    /// Uses listening history as a live, editorial-style track cover.
    @discardableResult
    func setListeningPosterArtwork(for track: Track) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return false }
        let previous = tracks[index]
        tracks[index].usesGeneratedArtwork = false
        tracks[index].artworkStyle = .listeningPoster
        guard saveLibrary() else {
            tracks[index] = previous
            return false
        }
        return true
    }

    /// Applies the persistent artwork defaults to all library tracks without deleting photos.
    @discardableResult
    func applyArtworkPreferencesToAllTracks() -> Bool {
        let previous = tracks
        tracks.indices.forEach { ArtworkPreferences.apply(to: &tracks[$0]) }
        guard saveLibrary() else {
            tracks = previous
            return false
        }
        return true
    }

    /// Restores the embedded cover, or the app's consistent default gradient if none exists.
    @discardableResult
    func resetArtwork(for track: Track) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return false }
        let previous = tracks[index]
        tracks[index].customArtworkFileName = nil
        tracks[index].usesGeneratedArtwork = nil
        tracks[index].artworkStyle = nil
        tracks[index].gradientHue1 = ArtworkTheme.violet.hue1
        tracks[index].gradientHue2 = ArtworkTheme.violet.hue2
        guard saveLibrary() else {
            tracks[index] = previous
            return false
        }
        removeCustomArtworkFile(for: previous)
        return true
    }

    private func removeCustomArtworkFile(for track: Track) {
        if let key = track.customArtworkFileName {
            ArtworkLoader.remove(byKey: key)
        }
        ArtworkStorage.removeIfPresent(track.customArtworkURL)
    }

    private func loadFavorites() {
        let raw = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        favoriteIDs = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favoriteIDs.map(\.uuidString), forKey: favoritesKey)
    }

    // MARK: - Import
    /// Imports audio files from the given URLs into the app's documents directory.
    /// File copying and metadata extraction run off the main actor; results are published on it.
    /// Skips duplicates based on file name.
    func importTracks(from urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return } // ignore overlapping imports (dedup race)
        isImporting = true
        let existingNames = Set(tracks.map(\.fileName))
        let docDir = Track.documentsDirectory

        Task {
            let outcome = await Self.processImports(
                urls: urls,
                existingNames: existingNames,
                docDir: docDir
            )
            var importedTracks = outcome.tracks
            importedTracks.indices.forEach { ArtworkPreferences.apply(to: &importedTracks[$0]) }
            tracks.append(contentsOf: importedTracks)
            if !importedTracks.isEmpty { saveLibrary() }
            if !outcome.errors.isEmpty {
                lastError = outcome.errors.joined(separator: "\n")
            }
            isImporting = false
        }
    }

    nonisolated private struct ImportOutcome: Sendable {
        let tracks: [Track]
        let errors: [String]
    }

    nonisolated private static func processImports(
        urls: [URL],
        existingNames: Set<String>,
        docDir: URL
    ) async -> ImportOutcome {
        let fm = FileManager.default
        var result: [Track] = []
        var errors: [String] = []
        var seen = existingNames

        for url in urls {
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            let fileName = url.lastPathComponent
            if seen.contains(fileName) {
                errors.append("\(fileName) was already imported.")
                continue
            }
            let destination = docDir.appendingPathComponent(fileName)

            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: url, to: destination)

                let meta = await extractMetadata(from: destination, fallbackName: fileName)
                // Drop any stale cache entry before overwriting the artwork file on re-import.
                await ArtworkLoader.remove(byKey: (fileName as NSString).deletingPathExtension + ".img")
                let artworkFileName = saveArtwork(meta.artwork, for: fileName, in: docDir, fm: fm)
                result.append(
                    Track(title: meta.title, artist: meta.artist, album: meta.album, genre: meta.genre,
                          fileName: fileName,
                          duration: meta.duration, dateImported: Date(), artworkFileName: artworkFileName)
                )
                seen.insert(fileName)
            } catch {
                errors.append("\(fileName): \(error.localizedDescription)")
            }
        }
        return ImportOutcome(tracks: result, errors: errors)
    }

    // MARK: - Delete
    /// Deletes a track. Removes the backing file first; only on success does it mutate the
    /// in-memory library and persist. Returns true on success so the caller can coordinate the
    /// player. If persistence fails, the load-time existence filter reconciles on next launch.
    @discardableResult
    func deleteTrack(_ track: Track) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: track.fileURL.path) {
            do {
                try fm.removeItem(at: track.fileURL)
            } catch {
                lastError = "\(track.title) could not be deleted: \(error.localizedDescription)"
                return false
            }
        }
        // Clean up both the embedded and user-selected artwork files (best-effort).
        ArtworkStorage.removeIfPresent(track.embeddedArtworkURL)
        ArtworkStorage.removeIfPresent(track.customArtworkURL)
        ArtworkLoader.remove(track)

        tracks.removeAll { $0.id == track.id }
        if favoriteIDs.remove(track.id) != nil { saveFavorites() }
        saveLibrary()
        return true
    }

    /// Deletes the local copies of the supplied tracks and returns only the tracks successfully
    /// removed. Callers use that result to remove matching playlist and playback references.
    @discardableResult
    func deleteTracks(_ tracksToDelete: [Track]) -> [Track] {
        let requestedIDs = Set(tracksToDelete.map(\.id))
        guard !requestedIDs.isEmpty else { return [] }

        let fm = FileManager.default
        var deleted: [Track] = []
        var errors: [String] = []

        for track in tracks where requestedIDs.contains(track.id) {
            if fm.fileExists(atPath: track.fileURL.path) {
                do {
                    try fm.removeItem(at: track.fileURL)
                } catch {
                    errors.append("\(track.title): \(error.localizedDescription)")
                    continue
                }
            }
            ArtworkStorage.removeIfPresent(track.embeddedArtworkURL)
            ArtworkStorage.removeIfPresent(track.customArtworkURL)
            ArtworkLoader.remove(track)
            deleted.append(track)
        }

        let deletedIDs = Set(deleted.map(\.id))
        guard !deletedIDs.isEmpty else {
            if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
            return []
        }

        tracks.removeAll { deletedIDs.contains($0.id) }
        if !favoriteIDs.isDisjoint(with: deletedIDs) {
            favoriteIDs.subtract(deletedIDs)
            saveFavorites()
        }
        saveLibrary()
        if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
        return deleted
    }

    func clearError() {
        lastError = nil
    }

    func reportArtworkError(_ message: String) {
        lastError = message
    }

    /// Libraries created by older app versions do not contain album or genre fields.
    /// Fill those values lazily from the existing local files without blocking launch.
    private func refreshMissingMetadata() {
        let currentMetadataVersion = 2
        let candidates = tracks.filter { $0.metadataScanVersion != currentMetadataVersion }
        guard !candidates.isEmpty else { return }

        Task {
            var changedCount = 0
            for track in candidates {
                let metadata = await Self.extractMetadata(
                    from: track.fileURL,
                    fallbackName: track.fileName
                )
                guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { continue }

                // Version 1 used the complete file name as the title when an MP3 had no tags.
                // Version 2 also recovers `Artist - Title` without overwriting a tagged title.
                if tracks[index].title == Self.cleanFileName(track.fileName) {
                    tracks[index].title = metadata.title
                }
                if tracks[index].artist == nil, let artist = metadata.artist {
                    tracks[index].artist = artist
                }
                if tracks[index].album == nil, let album = metadata.album {
                    tracks[index].album = album
                }
                if tracks[index].genre == nil, let genre = metadata.genre {
                    tracks[index].genre = genre
                }
                tracks[index].metadataScanVersion = currentMetadataVersion
                changedCount += 1
                // Persist progress for large libraries while keeping writes bounded.
                if changedCount.isMultiple(of: 25) { saveLibrary() }
            }
            if !changedCount.isMultiple(of: 25) { saveLibrary() }
        }
    }

    // MARK: - Metadata Extraction
    nonisolated private static func extractMetadata(
        from url: URL,
        fallbackName: String
    ) async -> (
        title: String,
        artist: String?,
        album: String?,
        genre: String?,
        duration: TimeInterval,
        artwork: Data?
    ) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        var duration: TimeInterval = 0
        let fileNameMetadata = TrackFileNameMetadata.parse(fallbackName)
        var title = fileNameMetadata.title
        var artist = fileNameMetadata.artist
        var album: String? = nil
        var genre: String? = nil
        var artwork: Data? = nil

        if let loadedDuration = try? await asset.load(.duration).seconds,
           loadedDuration.isFinite,
           !loadedDuration.isNaN,
           loadedDuration >= 0 {
            duration = loadedDuration
        }

        var metadata = (try? await asset.load(.commonMetadata)) ?? []
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let items = try? await asset.loadMetadata(for: format) {
                    metadata.append(contentsOf: items)
                }
            }
        }

        for item in metadata {
            if item.commonKey == .commonKeyTitle,
               let value = try? await item.load(.stringValue),
               !value.isEmpty {
                title = value
            }
            if item.commonKey == .commonKeyArtist,
               let value = try? await item.load(.stringValue),
               !value.isEmpty {
                artist = value
            }
            if item.identifier == .commonIdentifierAlbumName,
               let value = try? await item.load(.stringValue) {
                album = value.isEmpty ? nil : value
            }
            if item.identifier == .iTunesMetadataUserGenre ||
                item.identifier == .quickTimeMetadataGenre ||
                item.identifier == .quickTimeUserDataGenre ||
                item.identifier == .id3MetadataContentType,
               let value = try? await item.load(.stringValue) {
                genre = value.isEmpty ? nil : value
            }
            if item.commonKey == .commonKeyArtwork,
               let data = try? await item.load(.dataValue),
               !data.isEmpty {
                artwork = data
            }
        }

        return (title, artist, album, genre, duration, artwork)
    }

    /// Writes extracted cover art under `Artwork/<base>.img` and returns its file name, or nil.
    nonisolated private static func saveArtwork(
        _ data: Data?,
        for audioFileName: String,
        in docDir: URL,
        fm: FileManager
    ) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let artworkName = (audioFileName as NSString).deletingPathExtension + ".img"
        let artworkDir = docDir.appendingPathComponent("Artwork", isDirectory: true)
        do {
            try fm.createDirectory(at: artworkDir, withIntermediateDirectories: true)
            try data.write(to: artworkDir.appendingPathComponent(artworkName), options: .atomic)
            return artworkName
        } catch {
            print("Failed to save artwork for \(audioFileName): \(error)")
            return nil
        }
    }

    /// Strips file extension and cleans up underscores/hyphens for display.
    nonisolated private static func cleanFileName(_ name: String) -> String {
        let noExt = (name as NSString).deletingPathExtension
        return noExt
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    // MARK: - Persistence
    @discardableResult
    private func saveLibrary() -> Bool {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: saveURL, options: .atomic)
            return true
        } catch {
            lastError = "The music library could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    private func loadLibrary() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode([Track].self, from: data)
            // Filter out tracks whose audio files no longer exist on disk.
            tracks = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        } catch {
            lastError = "The music library could not be loaded: \(error.localizedDescription)"
        }
    }
}
