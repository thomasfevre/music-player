import SwiftUI

struct LibraryBrowserView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var category: Category = .recent

    enum Category: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case artists = "Artists"
        case albums = "Albums"
        case genres = "Genres"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                if category == .recent {
                    ForEach(recentTracks) { row(for: $0, queue: recentTracks) }
                } else {
                    ForEach(groups, id: \.name) { group in
                        NavigationLink {
                            LibraryCollectionView(title: group.name, tracks: group.tracks)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.name)
                                    Text("\(group.tracks.count) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: category.icon)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Browse")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Browse", selection: $category) {
                    ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var recentTracks: [Track] {
        Array(library.tracks.sorted { $0.dateImported > $1.dateImported }.prefix(100))
    }

    private var groups: [(name: String, tracks: [Track])] {
        let grouped = Dictionary(grouping: library.tracks) { track in
            switch category {
            case .artists: return track.displayArtist
            case .albums: return track.displayAlbum
            case .genres: return track.displayGenre
            case .recent: return ""
            }
        }
        return grouped.map { (name: $0.key, tracks: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func row(for track: Track, queue: [Track]) -> some View {
        TrackRowView(
            track: track,
            isActive: player.currentTrack == track,
            isPlaying: player.isPlaying && player.currentTrack == track,
            isFavorite: library.isFavorite(track)
        )
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { player.play(track, in: queue, source: .browser) }
    }
}

private extension LibraryBrowserView.Category {
    var icon: String {
        switch self {
        case .recent: return "clock"
        case .artists: return "person.2"
        case .albums: return "square.stack"
        case .genres: return "guitars"
        }
    }
}

private struct LibraryCollectionView: View {
    let title: String
    let tracks: [Track]

    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        List(tracks) { track in
            TrackRowView(
                track: track,
                isActive: player.currentTrack == track,
                isPlaying: player.isPlaying && player.currentTrack == track,
                isFavorite: library.isFavorite(track)
            )
            .listRowBackground(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { player.play(track, in: tracks, source: .browser) }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(title)
    }
}
