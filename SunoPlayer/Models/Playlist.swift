import Foundation

// MARK: - Playlist
/// A user-created ordered collection of track ids. Stores ids (not Tracks) so it stays valid
/// as the library changes; missing ids are skipped at resolution time.
struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    private(set) var trackIDs: [UUID]
    let dateCreated: Date

    init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.dateCreated = dateCreated
    }

    var count: Int { trackIDs.count }

    func contains(_ trackID: UUID) -> Bool { trackIDs.contains(trackID) }

    // MARK: Mutations (pure)

    /// Appends a track id, ignoring duplicates. Returns true if it was added.
    @discardableResult
    mutating func addTrack(_ trackID: UUID) -> Bool {
        guard !trackIDs.contains(trackID) else { return false }
        trackIDs.append(trackID)
        return true
    }

    mutating func removeTrack(_ trackID: UUID) {
        trackIDs.removeAll { $0 == trackID }
    }

    /// Reorders ids using SwiftUI `onMove` semantics, without depending on SwiftUI.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        trackIDs = Self.moved(trackIDs, fromOffsets: source, toOffset: destination)
    }

    /// Replaces the id list wholesale (used when reordering in resolved-track space).
    mutating func setTrackIDs(_ ids: [UUID]) {
        trackIDs = ids
    }

    /// Pure reorder matching SwiftUI `onMove` (destination is in the pre-removal index space).
    static func moved(_ ids: [UUID], fromOffsets source: IndexSet, toOffset destination: Int) -> [UUID] {
        var result = ids
        let moving = source.sorted().map { ids[$0] }
        for index in source.sorted(by: >) { result.remove(at: index) }
        let adjusted = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: max(0, min(adjusted, result.count)))
        return result
    }
}

// MARK: - PlaylistResolver
/// Pure resolution of a playlist's track ids against the current library, preserving playlist
/// order and skipping ids that no longer exist.
enum PlaylistResolver {
    static func tracks(for playlist: Playlist, in library: [Track]) -> [Track] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.trackIDs.compactMap { byID[$0] }
    }
}
