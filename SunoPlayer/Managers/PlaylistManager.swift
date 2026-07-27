import Foundation
import Combine

// MARK: - PlaylistManager
/// Manages user playlists: creation, edits, ordering, and persistence to a JSON file.
@MainActor
final class PlaylistManager: ObservableObject {

    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var lastError: String?

    private let saveFileName = "playlists.json"
    private let lastUsedPlaylistKey = "lastUsedManualPlaylistID"
    private var saveURL: URL {
        Track.documentsDirectory.appendingPathComponent(saveFileName)
    }

    init() {
        load()
    }

    // MARK: - CRUD

    @discardableResult
    func createPlaylist(name: String, trackIDs: [UUID] = []) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var uniqueIDs: [UUID] = []
        var seen = Set<UUID>()
        for trackID in trackIDs where seen.insert(trackID).inserted {
            uniqueIDs.append(trackID)
        }
        let playlist = Playlist(
            name: trimmed.isEmpty ? "New Playlist" : trimmed,
            trackIDs: uniqueIDs
        )
        playlists.append(playlist)
        save()
        return playlist
    }

    @discardableResult
    func createSmartPlaylist(name: String, rule: SmartPlaylistRule) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(
            name: trimmed.isEmpty ? rule.summary : trimmed,
            smartRule: rule
        )
        playlists.append(playlist)
        save()
        return playlist
    }

    func rename(_ playlist: Playlist, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = indexOf(playlist) else { return }
        playlists[index].name = trimmed
        save()
    }

    func delete(_ playlist: Playlist) {
        guard let index = indexOf(playlist) else { return }
        let removed = playlists.remove(at: index)
        guard save() else {
            playlists.insert(removed, at: index)
            return
        }
        removeArtworkFile(for: removed)
    }

    func deletePlaylists(at offsets: IndexSet) {
        let validOffsets = IndexSet(offsets.filter { playlists.indices.contains($0) })
        guard !validOffsets.isEmpty else { return }
        let deleting = validOffsets
            .map { playlists[$0] }
        let previous = playlists
        playlists.remove(atOffsets: validOffsets)
        guard save() else {
            playlists = previous
            return
        }
        deleting.forEach(removeArtworkFile)
    }

    // MARK: - Artwork

    @discardableResult
    func setCustomArtwork(_ data: Data, for playlist: Playlist) async -> Bool {
        guard indexOf(playlist) != nil else { return false }
        let fileName = "playlist-\(playlist.id.uuidString)-\(UUID().uuidString).jpg"
        do {
            try await Task.detached(priority: .userInitiated) {
                try ArtworkStorage.saveImage(
                    data,
                    fileName: fileName,
                    directory: Playlist.artworkDirectory
                )
            }.value
            guard let index = indexOf(playlist) else {
                await Task.detached {
                    ArtworkStorage.removeIfPresent(
                        Playlist.artworkDirectory.appendingPathComponent(fileName)
                    )
                }.value
                return false
            }
            let previous = playlists[index]
            playlists[index].artworkFileName = fileName
            guard save() else {
                playlists[index] = previous
                await Task.detached {
                    ArtworkStorage.removeIfPresent(
                        Playlist.artworkDirectory.appendingPathComponent(fileName)
                    )
                }.value
                return false
            }
            if let previousKey = previous.artworkFileName {
                ArtworkLoader.remove(byKey: previousKey)
            }
            await Task.detached {
                ArtworkStorage.removeIfPresent(previous.artworkURL)
            }.value
            return true
        } catch {
            lastError = "The playlist artwork could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    /// Selects an icon and color style, replacing a custom photo if one was in use.
    @discardableResult
    func setArtworkStyle(iconName: String, theme: ArtworkTheme, for playlist: Playlist) -> Bool {
        guard let index = indexOf(playlist) else { return false }
        let previous = playlists[index]
        playlists[index].artworkFileName = nil
        playlists[index].artworkIconName = iconName
        playlists[index].artworkHue1 = theme.hue1
        playlists[index].artworkHue2 = theme.hue2
        guard save() else {
            playlists[index] = previous
            return false
        }
        removeArtworkFile(for: previous)
        return true
    }

    @discardableResult
    func resetArtwork(for playlist: Playlist) -> Bool {
        guard let index = indexOf(playlist) else { return false }
        let previous = playlists[index]
        playlists[index].artworkFileName = nil
        playlists[index].artworkIconName = nil
        playlists[index].artworkHue1 = nil
        playlists[index].artworkHue2 = nil
        guard save() else {
            playlists[index] = previous
            return false
        }
        removeArtworkFile(for: previous)
        return true
    }

    // MARK: - Track membership

    var lastUsedManualPlaylist: Playlist? {
        guard let raw = UserDefaults.standard.string(forKey: lastUsedPlaylistKey),
              let id = UUID(uuidString: raw) else { return nil }
        return playlists.first { $0.id == id && $0.smartRule == nil }
    }

    func addTrack(_ trackID: UUID, to playlist: Playlist) {
        guard let index = indexOf(playlist) else { return }
        rememberLastUsedPlaylist(playlists[index])
        if playlists[index].addTrack(trackID) { save() }
    }

    /// Adds a batch in one mutation and performs at most one persistence write.
    func addTracks(_ trackIDs: [UUID], to playlist: Playlist) {
        guard let index = indexOf(playlist) else { return }
        rememberLastUsedPlaylist(playlists[index])
        if playlists[index].addTracks(trackIDs) > 0 { save() }
    }

    func removeTrack(_ trackID: UUID, from playlist: Playlist) {
        guard let index = indexOf(playlist) else { return }
        playlists[index].removeTrack(trackID)
        save()
    }

    private func rememberLastUsedPlaylist(_ playlist: Playlist) {
        guard playlist.smartRule == nil else { return }
        UserDefaults.standard.set(playlist.id.uuidString, forKey: lastUsedPlaylistKey)
    }

    func removeTracks(_ trackIDs: Set<UUID>, from playlist: Playlist) {
        guard let index = indexOf(playlist), !trackIDs.isEmpty else { return }
        for trackID in trackIDs {
            playlists[index].removeTrack(trackID)
        }
        save()
    }

    /// Reorders using offsets from the *resolved* (library-filtered) track list. Offsets are
    /// translated to stored-id space by identity, so ids whose tracks are missing from the
    /// library ("ghosts") don't corrupt the move; ghosts are kept at the end.
    func moveTracks(in playlist: Playlist, resolvedTracks: [Track], fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let index = indexOf(playlist) else { return }
        let resolvedIDs = resolvedTracks.map(\.id)
        let reordered = Playlist.moved(resolvedIDs, fromOffsets: source, toOffset: destination)
        let resolvedSet = Set(resolvedIDs)
        let ghosts = playlists[index].trackIDs.filter { !resolvedSet.contains($0) }
        playlists[index].setTrackIDs(reordered + ghosts)
        save()
    }

    /// Removes a deleted track from every playlist (call after deleting it from the library).
    func removeTrackFromAll(_ trackID: UUID) {
        var changed = false
        for index in playlists.indices where playlists[index].contains(trackID) {
            playlists[index].removeTrack(trackID)
            changed = true
        }
        if changed { save() }
    }

    /// Removes a set of deleted library tracks from every manual playlist in one save.
    func removeTracksFromAll(_ trackIDs: Set<UUID>) {
        guard !trackIDs.isEmpty else { return }
        var changed = false
        for index in playlists.indices where playlists[index].smartRule == nil {
            let before = playlists[index].count
            for trackID in trackIDs {
                playlists[index].removeTrack(trackID)
            }
            changed = changed || playlists[index].count != before
        }
        if changed { save() }
    }

    // MARK: - Lookup

    /// Returns the current stored copy of a playlist (so views reflect the latest edits).
    func current(_ playlist: Playlist) -> Playlist? {
        playlists.first { $0.id == playlist.id }
    }

    func clearError() {
        lastError = nil
    }

    func reportArtworkError(_ message: String) {
        lastError = message
    }

    private func indexOf(_ playlist: Playlist) -> Int? {
        playlists.firstIndex { $0.id == playlist.id }
    }

    private func removeArtworkFile(for playlist: Playlist) {
        if let key = playlist.artworkFileName {
            ArtworkLoader.remove(byKey: key)
        }
        ArtworkStorage.removeIfPresent(playlist.artworkURL)
    }

    // MARK: - Persistence

    @discardableResult
    private func save() -> Bool {
        do {
            try JSONEncoder().encode(playlists).write(to: saveURL, options: .atomic)
            return true
        } catch {
            lastError = "Playlists could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            playlists = try JSONDecoder().decode([Playlist].self, from: Data(contentsOf: saveURL))
        } catch {
            lastError = "Playlists could not be loaded: \(error.localizedDescription)"
        }
    }
}
