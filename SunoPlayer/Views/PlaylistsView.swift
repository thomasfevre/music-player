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
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                if playlists.playlists.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Playlists")
            .navigationDestination(for: UUID.self) { playlistID in
                PlaylistDetailView(playlistID: playlistID)
            }
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
                Button("Create", action: createAndOpenPlaylist)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        List {
            ForEach(playlists.playlists) { playlist in
                NavigationLink(value: playlist.id) {
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

    private func createAndOpenPlaylist() {
        let created = playlists.createPlaylist(name: newName)
        path.append(created.id)
    }
}

// MARK: - PlaylistDetailView
/// Shows the tracks of a single playlist with play / remove / reorder.
struct PlaylistDetailView: View {
    let playlistID: UUID

    @EnvironmentObject var playlists: PlaylistManager
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager

    @State private var showAddTracks = false
    @State private var showRenameAlert = false
    @State private var renamedName = ""

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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTracks = true
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .accessibilityLabel("Add Tracks")
                .disabled(playlist == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renamedName = playlist?.name ?? ""
                        showRenameAlert = true
                    } label: {
                        Label("Rename Playlist", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(playlist == nil)
            }
        }
        .sheet(isPresented: $showAddTracks) {
            AddTracksToPlaylistView(playlistID: playlistID)
                .environmentObject(playlists)
                .environmentObject(library)
                .environmentObject(player)
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("Name", text: $renamedName)
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: renamePlaylist)
                .disabled(renamedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func renamePlaylist() {
        guard let playlist else { return }
        playlists.rename(playlist, to: renamedName)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .thin))
                .foregroundColor(.white.opacity(0.5))
            Text("No tracks yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Choose songs from your downloaded music.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button {
                showAddTracks = true
            } label: {
                Label("Add Tracks", systemImage: "text.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .padding(.top, 4)
        }
        .padding()
    }
}
