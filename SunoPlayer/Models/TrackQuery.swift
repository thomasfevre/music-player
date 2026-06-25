import Foundation

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
                $0.displayArtist.localizedCaseInsensitiveContains(trimmed)
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
