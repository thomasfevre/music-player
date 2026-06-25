import SwiftUI

// MARK: - PlaylistsView
/// Lists user playlists with create / delete, presented as a sheet from the library.
struct PlaylistsView: View {
    @EnvironmentObject var playlists: PlaylistManager
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateAlert = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if playlists.playlists.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showCreateAlert) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { playlists.createPlaylist(name: newName) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        List {
            ForEach(playlists.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            Text("\(playlist.count) track\(playlist.count == 1 ? "" : "s")")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.04))
            }
            .onDelete { playlists.deletePlaylists(at: $0) }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 52, weight: .thin))
                .foregroundColor(.white.opacity(0.5))
            Text("No Playlists")
                .font(.title3.bold())
                .foregroundColor(.white)
            Text("Tap + to create your first playlist.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding()
    }
}

// MARK: - PlaylistDetailView
/// Shows the tracks of a single playlist with play / remove / reorder.
struct PlaylistDetailView: View {
    let playlistID: UUID

    @EnvironmentObject var playlists: PlaylistManager
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager

    private var playlist: Playlist? {
        playlists.playlists.first { $0.id == playlistID }
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return PlaylistResolver.tracks(for: playlist, in: library.tracks)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if tracks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(tracks) { track in
                        TrackRowView(
                            track: track,
                            isActive: player.currentTrack?.id == track.id,
                            isPlaying: player.isPlaying && player.currentTrack?.id == track.id,
                            isFavorite: library.isFavorite(track)
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.play(track, in: tracks)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    .onDelete(perform: removeTracks)
                    .onMove(perform: moveTracks)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !tracks.isEmpty { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let first = tracks.first else { return }
                    player.play(first, in: tracks)
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(tracks.isEmpty)
            }
        }
    }

    private func removeTracks(at offsets: IndexSet) {
        guard let playlist else { return }
        for index in offsets { playlists.removeTrack(tracks[index].id, from: playlist) }
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        guard let playlist else { return }
        playlists.moveTracks(in: playlist, resolvedTracks: tracks, fromOffsets: source, toOffset: destination)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .thin))
                .foregroundColor(.white.opacity(0.5))
            Text("No tracks yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Add tracks from the library using the ⋯ menu.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
