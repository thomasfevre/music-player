import Foundation
import Combine

// MARK: - PlaylistManager
/// Manages user playlists: creation, edits, ordering, and persistence to a JSON file.
@MainActor
final class PlaylistManager: ObservableObject {

    @Published private(set) var playlists: [Playlist] = []

    private let saveFileName = "playlists.json"
    private var saveURL: URL {
        Track.documentsDirectory.appendingPathComponent(saveFileName)
    }

    init() {
        load()
    }

    // MARK: - CRUD

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(name: trimmed.isEmpty ? "New Playlist" : trimmed)
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
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Track membership

    func addTrack(_ trackID: UUID, to playlist: Playlist) {
        guard let index = indexOf(playlist) else { return }
        if playlists[index].addTrack(trackID) { save() }
    }

    func removeTrack(_ trackID: UUID, from playlist: Playlist) {
        guard let index = indexOf(playlist) else { return }
        playlists[index].removeTrack(trackID)
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

    // MARK: - Lookup

    /// Returns the current stored copy of a playlist (so views reflect the latest edits).
    func current(_ playlist: Playlist) -> Playlist? {
        playlists.first { $0.id == playlist.id }
    }

    private func indexOf(_ playlist: Playlist) -> Int? {
        playlists.firstIndex { $0.id == playlist.id }
    }

    // MARK: - Persistence

    private func save() {
        do {
            try JSONEncoder().encode(playlists).write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save playlists: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            playlists = try JSONDecoder().decode([Playlist].self, from: Data(contentsOf: saveURL))
        } catch {
            print("Failed to load playlists: \(error)")
        }
    }
}
