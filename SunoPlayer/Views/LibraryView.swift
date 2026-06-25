import SwiftUI
import UniformTypeIdentifiers

// MARK: - LibraryView
/// Main library screen showing all imported tracks, search, sort, and import controls.
struct LibraryView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var playlists: PlaylistManager

    @Binding var showNowPlaying: Bool

    @State private var showFilePicker = false
    @State private var showSortMenu = false
    @State private var showPlaylists = false

    // Bottom padding when mini player is visible
    private var listBottomPadding: CGFloat {
        player.currentTrack != nil ? 88 : 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                if library.displayedTracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
            }
            .navigationTitle("Music Player")
            .navigationBarTitleDisplayMode(.large)
            // Keep the header light on scroll: no nav-bar background. The search field keeps
            // its own liquid-glass material.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbarItems }
            .searchable(
                text: $library.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search tracks…"
            )
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    library.importTracks(from: urls)
                }
            }
            .sheet(isPresented: $showPlaylists) {
                PlaylistsView()
                    .environmentObject(playlists)
                    .environmentObject(library)
                    .environmentObject(player)
            }
        }
    }

    // MARK: Track List
    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(library.displayedTracks) { track in
                    TrackRowView(
                        track: track,
                        isActive: player.currentTrack?.id == track.id,
                        isPlaying: player.isPlaying && player.currentTrack?.id == track.id,
                        isFavorite: library.isFavorite(track)
                    )
                    .onTapGesture {
                        player.play(track, in: library.displayedTracks)
                        showNowPlaying = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .contextMenu {
                        Button {
                            library.toggleFavorite(track)
                        } label: {
                            let fav = library.isFavorite(track)
                            Label(fav ? "Remove from Favorites" : "Add to Favorites",
                                  systemImage: fav ? "heart.slash" : "heart")
                        }
                        Menu {
                            ForEach(playlists.playlists) { playlist in
                                Button {
                                    if playlist.contains(track.id) {
                                        playlists.removeTrack(track.id, from: playlist)
                                    } else {
                                        playlists.addTrack(track.id, to: playlist)
                                    }
                                } label: {
                                    Label(playlist.name,
                                          systemImage: playlist.contains(track.id) ? "checkmark" : "music.note.list")
                                }
                            }
                            Divider()
                            Button {
                                let created = playlists.createPlaylist(name: "New Playlist")
                                playlists.addTrack(track.id, to: created)
                            } label: {
                                Label("New Playlist", systemImage: "plus")
                            }
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                        }
                        Button(role: .destructive) {
                            // Update the player only after the filesystem delete succeeds,
                            // so the queue can never reference a still-present file (and
                            // vice-versa). Atomic — no rollback needed.
                            if library.deleteTrack(track) {
                                player.handleTrackDeleted(track)
                                playlists.removeTrackFromAll(track.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, listBottomPadding + 16)
        }
    }

    // MARK: Empty State
    private var emptyState: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hue: 0.75, saturation: 0.6, brightness: 0.5).opacity(0.5),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "music.note.list")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.75, saturation: 0.8, brightness: 0.9),
                                Color(hue: 0.65, saturation: 0.7, brightness: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("No Tracks Yet")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Import your first AI-generated song\nfrom the Files app.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showFilePicker = true
            } label: {
                Label("Import Music", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.75, saturation: 0.6, brightness: 0.9),
                                Color(hue: 0.65, saturation: 0.7, brightness: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hue: 0.75, saturation: 0.5, brightness: 0.5), radius: 20, y: 6)
            }
        }
        .padding()
    }

    // MARK: Toolbar
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                // Playlists
                Button {
                    showPlaylists = true
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                // Favorites filter toggle
                Button {
                    library.showFavoritesOnly.toggle()
                } label: {
                    Image(systemName: library.showFavoritesOnly ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(library.showFavoritesOnly ? .pink : .white.opacity(0.8))
                }

                // Sort menu
                Menu {
                    ForEach(SortOrder.allCases) { order in
                        Button {
                            library.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if library.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                // Import button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showFilePicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
    }
}
