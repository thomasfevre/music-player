import Foundation

struct SavedLibraryFilter: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var query: String
    var favoritesOnly: Bool
    var sortOrder: SortOrder

    init(id: UUID = UUID(), name: String, query: String, favoritesOnly: Bool, sortOrder: SortOrder = .newest) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Saved Filter" : name
        self.query = query
        self.favoritesOnly = favoritesOnly
        self.sortOrder = sortOrder
    }

    private static let defaultsKey = "savedLibraryFilters"

    static func load() -> [SavedLibraryFilter] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([SavedLibraryFilter].self, from: data)) ?? []
    }

    static func save(_ filters: [SavedLibraryFilter]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(filters), forKey: defaultsKey)
    }
}

// MARK: - TrackQuery
/// Pure, testable filtering + sorting for the library's displayed tracks.
enum TrackQuery {
    /// - Parameter favoriteIDs: when non-nil, restricts the result to tracks whose id is in the set
    ///   (used by the "Favorites only" filter); when nil, no favorite filtering is applied.
    static func apply(
        tracks: [Track],
        searchText: String,
        sortOrder: SortOrder,
        favoriteIDs: Set<UUID>? = nil
    ) -> [Track] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let bySearch = trimmed.isEmpty
            ? tracks
            : tracks.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) ||
                $0.displayArtist.localizedCaseInsensitiveContains(trimmed) ||
                ($0.album?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
                ($0.genre?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        let filtered = favoriteIDs.map { ids in bySearch.filter { ids.contains($0.id) } } ?? bySearch

        return filtered.sorted { a, b in
            switch sortOrder {
            case .newest: return a.dateImported > b.dateImported
            case .oldest: return a.dateImported < b.dateImported
            case .title:  return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }
}
