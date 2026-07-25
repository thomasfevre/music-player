import SwiftUI

// MARK: - AddTracksToPlaylistView
/// Adds several downloaded tracks to a playlist from one searchable, scrollable checklist.
struct AddTracksToPlaylistView: View {
    let playlistID: UUID

    @EnvironmentObject var playlists: PlaylistManager
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTrackIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .newest

    private var playlist: Playlist? {
        playlists.playlists.first { $0.id == playlistID }
    }

    private var sortedTracks: [Track] {
        TrackQuery.apply(
            tracks: library.tracks,
            searchText: "",
            sortOrder: sortOrder
        )
    }

    private var visibleTracks: [Track] {
        TrackQuery.apply(
            tracks: library.tracks,
            searchText: searchText,
            sortOrder: sortOrder
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if visibleTracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
            }
            .navigationTitle("Add Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search downloaded music")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(addButtonTitle, action: addSelectedTracks)
                        .fontWeight(.semibold)
                        .disabled(selectedTrackIDs.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases) { order in
                Button {
                    sortOrder = order
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort Tracks")
    }

    private var trackList: some View {
        let existingTrackIDs = Set(playlist?.trackIDs ?? [])

        return List(visibleTracks) { track in
            let alreadyAdded = existingTrackIDs.contains(track.id)
            let isSelected = selectedTrackIDs.contains(track.id)

            Button {
                toggleSelection(of: track, isAlreadyAdded: alreadyAdded)
            } label: {
                HStack(spacing: 8) {
                    TrackRowView(
                        track: track,
                        isActive: player.currentTrack?.id == track.id,
                        isPlaying: player.isPlaying && player.currentTrack?.id == track.id,
                        isFavorite: library.isFavorite(track)
                    )
                    .allowsHitTesting(false)

                    Image(systemName: selectionIcon(isSelected: isSelected, isAlreadyAdded: alreadyAdded))
                        .font(.system(size: 24))
                        .foregroundStyle(selectionColor(isSelected: isSelected, isAlreadyAdded: alreadyAdded))
                }
                .contentShape(Rectangle())
            }
            .disabled(alreadyAdded)
            .buttonStyle(.plain)
            .accessibilityLabel(track.title)
            .accessibilityValue(accessibilityValue(isSelected: isSelected, isAlreadyAdded: alreadyAdded))
            .accessibilityAddTraits(selectionTraits(isSelected: isSelected, isAlreadyAdded: alreadyAdded))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 12))
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        let content = emptyStateContent

        return VStack(spacing: 12) {
            Image(systemName: content.icon)
                .font(.system(size: 44, weight: .thin))
                .foregroundColor(.white.opacity(0.5))
            Text(content.title)
                .font(.headline)
                .foregroundColor(.white)
            Text(content.message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyStateContent: (icon: String, title: String, message: String) {
        if library.tracks.isEmpty {
            return ("music.note", "No Downloaded Tracks", "Import music into your library first.")
        }
        return ("magnifyingglass", "No Results", "Try a different title or artist.")
    }

    private var addButtonTitle: String {
        selectedTrackIDs.isEmpty ? "Add" : "Add (\(selectedTrackIDs.count))"
    }

    private func toggleSelection(of track: Track, isAlreadyAdded: Bool) {
        guard !isAlreadyAdded else { return }
        if selectedTrackIDs.contains(track.id) {
            selectedTrackIDs.remove(track.id)
        } else {
            selectedTrackIDs.insert(track.id)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func selectionIcon(isSelected: Bool, isAlreadyAdded: Bool) -> String {
        isAlreadyAdded || isSelected ? "checkmark.circle.fill" : "circle"
    }

    private func selectionColor(isSelected: Bool, isAlreadyAdded: Bool) -> Color {
        if isAlreadyAdded { return .white.opacity(0.25) }
        return isSelected ? .purple : .white.opacity(0.35)
    }

    private func accessibilityValue(isSelected: Bool, isAlreadyAdded: Bool) -> String {
        if isAlreadyAdded { return "Already in playlist" }
        return isSelected ? "Selected" : "Not selected"
    }

    private func selectionTraits(isSelected: Bool, isAlreadyAdded: Bool) -> AccessibilityTraits {
        isAlreadyAdded || isSelected ? .isSelected : []
    }

    private func addSelectedTracks() {
        guard let playlist else { return }
        let orderedIDs = sortedTracks.map(\.id).filter(selectedTrackIDs.contains)
        playlists.addTracks(orderedIDs, to: playlist)
        dismiss()
    }
}
