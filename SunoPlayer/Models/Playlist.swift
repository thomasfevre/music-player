import Foundation

enum SmartPlaylistRule: Codable, Equatable {
    case artist(String)
    case album(String)
    case genre(String)
    case favorites
    case recentlyAdded(days: Int)

    func matches(_ track: Track, favoriteIDs: Set<UUID>, now: Date = Date()) -> Bool {
        switch self {
        case .artist(let value):
            return track.artist?.localizedCaseInsensitiveContains(value) ?? false
        case .album(let value):
            return track.album?.localizedCaseInsensitiveContains(value) ?? false
        case .genre(let value):
            return track.genre?.localizedCaseInsensitiveContains(value) ?? false
        case .favorites:
            return favoriteIDs.contains(track.id)
        case .recentlyAdded(let days):
            guard days > 0 else { return false }
            return track.dateImported >= now.addingTimeInterval(-Double(days) * 86_400)
        }
    }

    var summary: String {
        switch self {
        case .artist(let value): return "Artist contains \(value)"
        case .album(let value): return "Album contains \(value)"
        case .genre(let value): return "Genre contains \(value)"
        case .favorites: return "Favorites"
        case .recentlyAdded(let days): return "Added in the last \(days) days"
        }
    }
}

// MARK: - Playlist
/// A user-created ordered collection of track ids. Stores ids (not Tracks) so it stays valid
/// as the library changes; missing ids are skipped at resolution time.
struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    private(set) var trackIDs: [UUID]
    let dateCreated: Date
    var smartRule: SmartPlaylistRule?

    init(
        id: UUID = UUID(),
        name: String,
        trackIDs: [UUID] = [],
        dateCreated: Date = Date(),
        smartRule: SmartPlaylistRule? = nil
    ) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.dateCreated = dateCreated
        self.smartRule = smartRule
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

    /// Appends several track ids in order, ignoring duplicates already in the playlist or input.
    /// Returns the number of tracks that were added.
    @discardableResult
    mutating func addTracks(_ newTrackIDs: [UUID]) -> Int {
        var existingIDs = Set(trackIDs)
        var addedCount = 0
        for trackID in newTrackIDs where existingIDs.insert(trackID).inserted {
            trackIDs.append(trackID)
            addedCount += 1
        }
        return addedCount
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
    static func moved<Element>(
        _ elements: [Element],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Element] {
        var result = elements
        let moving = source.sorted().map { elements[$0] }
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
    static func tracks(
        for playlist: Playlist,
        in library: [Track],
        favoriteIDs: Set<UUID> = [],
        now: Date = Date()
    ) -> [Track] {
        if let rule = playlist.smartRule {
            return library
                .filter { rule.matches($0, favoriteIDs: favoriteIDs, now: now) }
                .sorted { $0.dateImported > $1.dateImported }
        }
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.trackIDs.compactMap { byID[$0] }
    }
}
