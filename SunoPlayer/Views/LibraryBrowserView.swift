import SwiftUI

struct LibraryBrowserView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var category: Category = .recent

    enum Category: String, CaseIterable, Identifiable {
        case recent = "Recently Played"
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
        let ids = player.listeningHistory.history.recentEvents
            .filter { $0.kind == .playback }
            .reversed()
            .reduce(into: [UUID]()) { result, event in
                if !result.contains(event.trackID) { result.append(event.trackID) }
            }
        let byID = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0) })
        let currentID = player.currentTrack?.id
        return ([currentID].compactMap { $0 } + ids).reduce(into: [Track]()) { result, id in
            guard let track = byID[id], !result.contains(where: { $0.id == id }) else { return }
            result.append(track)
        }
    }

    private var groups: [(name: String, tracks: [Track])] {
        var grouped: [String: (name: String, tracks: [Track])] = [:]

        for track in library.tracks {
            let values: [String]
            switch category {
            case .artists:
                let components = TrackBrowseMetadata.components(from: track.artist)
                values = components.isEmpty ? [track.displayArtist] : components
            case .albums:
                values = [track.displayAlbum]
            case .genres:
                let components = TrackBrowseMetadata.components(from: track.genre)
                values = components.isEmpty ? [track.displayGenre] : components
            case .recent:
                values = []
            }

            for value in values {
                let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                var group = grouped[key] ?? (name: value, tracks: [])
                group.tracks.append(track)
                grouped[key] = group
            }
        }

        return grouped.values.map { (name: $0.name, tracks: $0.tracks.sorted { $0.title < $1.title }) }
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
