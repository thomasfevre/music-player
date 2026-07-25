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
    @State private var showPlaylists = false
    @State private var showBrowser = false
    @State private var pendingDeletion: Track?
    @State private var artworkTrack: Track?

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
            .safeAreaInset(edge: .top, spacing: 0) {
                libraryActions
            }
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
            .sheet(isPresented: $showBrowser) {
                LibraryBrowserView()
                    .environmentObject(library)
                    .environmentObject(player)
            }
            .sheet(item: $artworkTrack) { track in
                TrackArtworkEditorView(trackID: track.id)
                    .environmentObject(library)
            }
            .alert(item: $pendingDeletion) { track in
                Alert(
                    title: Text("Delete Downloaded File?"),
                    message: Text("“\(track.title)” will be permanently removed from this iPhone and from every playlist."),
                    primaryButton: .destructive(Text("Delete")) { delete(track) },
                    secondaryButton: .cancel()
                )
            }
            .alert(
                "Music Library Error",
                isPresented: Binding(
                    get: { library.lastError != nil },
                    set: { if !$0 { library.clearError() } }
                )
            ) {
                Button("OK") { library.clearError() }
            } message: {
                Text(library.lastError ?? "")
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
                            player.enqueueNext(track)
                        } label: {
                            Label("Play Next", systemImage: "text.insert")
                        }
                        Button {
                            player.enqueueLater(track)
                        } label: {
                            Label("Play Later", systemImage: "text.append")
                        }
                        Button {
                            library.toggleFavorite(track)
                        } label: {
                            let fav = library.isFavorite(track)
                            Label(fav ? "Remove from Favorites" : "Add to Favorites",
                                  systemImage: fav ? "heart.slash" : "heart")
                        }
                        Button {
                            artworkTrack = track
                        } label: {
                            Label("Customize Artwork", systemImage: "photo.badge.plus")
                        }
                        Menu {
                            ForEach(playlists.playlists.filter { $0.smartRule == nil }) { playlist in
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
                            pendingDeletion = track
                        } label: {
                            Label("Delete Downloaded File", systemImage: "trash")
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

    // MARK: Library actions
    private var libraryActions: some View {
        HStack(spacing: 0) {
            Button {
                showBrowser = true
            } label: {
                LibraryActionLabel(title: "Browse", systemImage: "square.grid.2x2")
            }

            Button {
                showPlaylists = true
            } label: {
                LibraryActionLabel(title: "Playlists", systemImage: "music.note.list")
            }

            Button {
                library.showFavoritesOnly.toggle()
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                LibraryActionLabel(
                    title: "Favorites",
                    systemImage: library.showFavoritesOnly ? "heart.fill" : "heart",
                    tint: library.showFavoritesOnly ? .pink : .white.opacity(0.82)
                )
            }

            Menu {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        library.sortOrder = order
                    } label: {
                        Label(
                            order.rawValue,
                            systemImage: library.sortOrder == order ? "checkmark" : "circle"
                        )
                    }
                }
            } label: {
                LibraryActionLabel(title: "Sort", systemImage: "arrow.up.arrow.down")
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showFilePicker = true
            } label: {
                LibraryActionLabel(title: "Import", systemImage: "plus.circle.fill")
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func delete(_ track: Track) {
        // The queue and playlists update only after the file operation succeeds.
        if library.deleteTrack(track) {
            player.handleTrackDeleted(track)
            playlists.removeTrackFromAll(track.id)
        }
    }
}

private struct LibraryActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .white.opacity(0.82)

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(height: 22)
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
}
