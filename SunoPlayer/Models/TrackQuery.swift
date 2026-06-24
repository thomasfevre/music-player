import Foundation

// MARK: - TrackQuery
/// Pure, testable filtering + sorting for the library's displayed tracks.
enum TrackQuery {
    static func apply(tracks: [Track], searchText: String, sortOrder: SortOrder) -> [Track] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? tracks
            : tracks.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) ||
                $0.displayArtist.localizedCaseInsensitiveContains(trimmed)
            }

        return filtered.sorted { a, b in
            switch sortOrder {
            case .newest: return a.dateImported > b.dateImported
            case .oldest: return a.dateImported < b.dateImported
            case .title:  return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }
}
