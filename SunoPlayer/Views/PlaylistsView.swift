import SwiftUI
import UniformTypeIdentifiers

// MARK: - PlaylistsView
struct PlaylistsView: View {
    @EnvironmentObject var playlists: PlaylistManager
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateAlert = false
    @State private var showSmartEditor = false
    @State private var showImporter = false
    @State private var newName = ""
    @State private var path: [UUID] = []
    @State private var importMessage: String?
    @State private var artworkPlaylist: Playlist?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                if playlists.playlists.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Playlists")
            .navigationDestination(for: UUID.self) { PlaylistDetailView(playlistID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newName = ""
                            showCreateAlert = true
                        } label: {
                            Label("New Playlist", systemImage: "music.note.list")
                        }
                        Button {
                            showSmartEditor = true
                        } label: {
                            Label("New Smart Playlist", systemImage: "wand.and.stars")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import M3U", systemImage: "square.and.arrow.down")
                        }
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
            .alert(
                "M3U Import",
                isPresented: Binding(
                    get: { importMessage != nil },
                    set: { if !$0 { importMessage = nil } }
                )
            ) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .alert(
                "Playlist Error",
                isPresented: Binding(
                    get: { playlists.lastError != nil },
                    set: { if !$0 { playlists.clearError() } }
                )
            ) {
                Button("OK") { playlists.clearError() }
            } message: {
                Text(playlists.lastError ?? "")
            }
            .sheet(isPresented: $showSmartEditor) {
                SmartPlaylistEditorView { created in path.append(created.id) }
                    .environmentObject(playlists)
            }
            .sheet(item: $artworkPlaylist) { playlist in
                PlaylistArtworkEditorView(playlistID: playlist.id)
                    .environmentObject(playlists)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.m3uPlaylist, .plainText]
            ) { result in
                switch result {
                case .success(let url):
                    importM3U(from: url)
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        importMessage = "The playlist could not be selected: \(error.localizedDescription)"
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        List {
            ForEach(playlists.playlists) { playlist in
                NavigationLink(value: playlist.id) {
                    HStack(spacing: 14) {
                        PlaylistArtworkView(playlist: playlist, size: 48, cornerRadius: 11)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            let count = resolvedTracks(for: playlist).count
                            Text("\(count) track\(count == 1 ? "" : "s")")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.45))
                            if let rule = playlist.smartRule {
                                Text(rule.summary)
                                    .font(.caption2)
                                    .foregroundColor(.purple.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.04))
                .contextMenu {
                    Button {
                        artworkPlaylist = playlist
                    } label: {
                        Label("Customize Artwork", systemImage: "photo.badge.plus")
                    }
                }
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
            Text("Tap + to create or import your first playlist.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
            Button("Create Playlist") {
                newName = ""
                showCreateAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding()
    }

    private func resolvedTracks(for playlist: Playlist) -> [Track] {
        PlaylistResolver.tracks(
            for: playlist,
            in: library.tracks,
            favoriteIDs: library.favoriteIDs
        )
    }

    private func createAndOpenPlaylist() {
        let created = playlists.createPlaylist(name: newName)
        path.append(created.id)
    }

    private func importM3U(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ??
                    String(data: data, encoding: .isoLatin1) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let result = M3UPlaylistCodec.resolve(text, in: library.tracks)
            let name = url.deletingPathExtension().lastPathComponent
            let created = playlists.createPlaylist(name: name)
            playlists.addTracks(result.tracks.map(\.id), to: created)
            if result.missingFileNames.isEmpty {
                path.append(created.id)
            } else {
                importMessage = "\(result.tracks.count) tracks imported. \(result.missingFileNames.count) files were not found in your library."
            }
        } catch {
            importMessage = "The playlist could not be imported: \(error.localizedDescription)"
        }
    }
}

private enum PlaylistTrackSort: String, CaseIterable, Identifiable {
    case manual = "Playlist Order"
    case title = "Title"
    case artist = "Artist"
    case newest = "Newest"
    case oldest = "Oldest"
    var id: String { rawValue }
}

// MARK: - PlaylistDetailView
struct PlaylistDetailView: View {
    let playlistID: UUID

    @EnvironmentObject var playlists: PlaylistManager
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.editMode) private var editMode

    @State private var showAddTracks = false
    @State private var showRenameAlert = false
    @State private var renamedName = ""
    @State private var searchText = ""
    @State private var sortOrder: PlaylistTrackSort = .manual
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showExporter = false
    @State private var exportDocument = M3UPlaylistDocument()
    @State private var operationMessage: String?
    @State private var showArtworkEditor = false
    @State private var artworkTrack: Track?

    private var playlist: Playlist? {
        playlists.playlists.first { $0.id == playlistID }
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return PlaylistResolver.tracks(
            for: playlist,
            in: library.tracks,
            favoriteIDs: library.favoriteIDs
        )
    }

    private var visibleTracks: [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? tracks
            : tracks.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.displayArtist.localizedCaseInsensitiveContains(query) ||
                ($0.album?.localizedCaseInsensitiveContains(query) ?? false) ||
                ($0.genre?.localizedCaseInsensitiveContains(query) ?? false)
            }
        return filtered.sorted {
            switch sortOrder {
            case .manual: return orderIndex($0) < orderIndex($1)
            case .title: return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            case .artist: return $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending
            case .newest: return $0.dateImported > $1.dateImported
            case .oldest: return $0.dateImported < $1.dateImported
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if tracks.isEmpty { emptyState } else { trackList }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search this playlist")
        .onChange(of: searchText) {
            guard isSelecting else { return }
            selectedIDs.formIntersection(Set(visibleTracks.map(\.id)))
        }
        .toolbar { toolbarItems }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .sheet(isPresented: $showAddTracks) {
            AddTracksToPlaylistView(playlistID: playlistID)
                .environmentObject(playlists)
                .environmentObject(library)
                .environmentObject(player)
        }
        .sheet(isPresented: $showArtworkEditor) {
            PlaylistArtworkEditorView(playlistID: playlistID)
                .environmentObject(playlists)
        }
        .sheet(item: $artworkTrack) { track in
            TrackArtworkEditorView(trackID: track.id)
                .environmentObject(library)
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("Name", text: $renamedName)
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: renamePlaylist)
                .disabled(renamedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "Playlist Export",
            isPresented: Binding(
                get: { operationMessage != nil },
                set: { if !$0 { operationMessage = nil } }
            )
        ) {
            Button("OK") { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .m3uPlaylist,
            defaultFilename: playlist?.name ?? "Playlist"
        ) { result in
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                operationMessage = "The playlist could not be exported: \(error.localizedDescription)"
            }
        }
    }

    private var trackList: some View {
        List {
            Section {
                summary
                    .listRowBackground(Color.clear)
            }
            ForEach(visibleTracks) { track in
                HStack(spacing: 8) {
                    if isSelecting {
                        Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedIDs.contains(track.id) ? .purple : .secondary)
                    }
                    TrackRowView(
                        track: track,
                        isActive: player.currentTrack == track,
                        isPlaying: player.isPlaying && player.currentTrack == track,
                        isFavorite: library.isFavorite(track)
                    )
                    .allowsHitTesting(false)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelecting {
                        toggleSelection(track.id)
                    } else {
                        player.play(track, in: visibleTracks)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                .contextMenu {
                    Button { player.enqueueNext(track) } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }
                    Button { player.enqueueLater(track) } label: {
                        Label("Play Later", systemImage: "text.append")
                    }
                    Button {
                        artworkTrack = track
                    } label: {
                        Label("Customize Artwork", systemImage: "photo.badge.plus")
                    }
                    if playlist?.smartRule == nil {
                        Button(role: .destructive) {
                            if let playlist { playlists.removeTrack(track.id, from: playlist) }
                        } label: {
                            Label("Remove from Playlist", systemImage: "minus.circle")
                        }
                    }
                }
            }
            .onDelete(perform: canManuallyEdit ? removeTracks : nil)
            .onMove(perform: canReorder ? moveTracks : nil)
        }
        .scrollContentBackground(.hidden)
    }

    private var summary: some View {
        HStack(spacing: 14) {
            if let playlist {
                Button {
                    showArtworkEditor = true
                } label: {
                    PlaylistArtworkView(playlist: playlist, size: 72, cornerRadius: 16)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .purple)
                                .background(.black, in: Circle())
                                .offset(x: 5, y: 5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Customize Playlist Artwork")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s")")
                    .font(.headline)
                Text(DurationFormatter.format(tracks.reduce(0) { $0 + $1.duration }))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let rule = playlist?.smartRule {
                Label(rule.summary, systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if canManuallyEdit &&
                !isSelecting &&
                (canReorder || editMode?.wrappedValue.isEditing == true) {
                EditButton()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                guard let first = visibleTracks.first else { return }
                player.play(first, in: visibleTracks)
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(visibleTracks.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if playlist?.smartRule == nil {
                Button {
                    showAddTracks = true
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .accessibilityLabel("Add Tracks")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(PlaylistTrackSort.allCases) { Text($0.rawValue).tag($0) }
                }
                if playlist?.smartRule == nil {
                    Button { showAddTracks = true } label: {
                        Label("Add Tracks", systemImage: "text.badge.plus")
                    }
                    Button {
                        isSelecting = true
                    } label: {
                        Label("Select Tracks", systemImage: "checkmark.circle")
                    }
                }
                Button {
                    renamedName = playlist?.name ?? ""
                    showRenameAlert = true
                } label: {
                    Label("Rename Playlist", systemImage: "pencil")
                }
                Button {
                    showArtworkEditor = true
                } label: {
                    Label("Customize Artwork", systemImage: "photo.badge.plus")
                }
                Button {
                    exportDocument = M3UPlaylistDocument(text: M3UPlaylistCodec.encode(tracks))
                    showExporter = true
                } label: {
                    Label("Export M3U", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(playlist == nil)
        }
    }

    private var selectionBar: some View {
        HStack {
            Button("Cancel") {
                isSelecting = false
                selectedIDs.removeAll()
            }
            Spacer()
            Button(selectedIDs.count == visibleTracks.count ? "Deselect All" : "Select All") {
                if selectedIDs.count == visibleTracks.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(visibleTracks.map(\.id))
                }
            }
            Spacer()
            Button("Remove (\(selectedIDs.count))", role: .destructive) {
                guard let playlist else { return }
                playlists.removeTracks(selectedIDs, from: playlist)
                selectedIDs.removeAll()
                isSelecting = false
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if let playlist {
                Button {
                    showArtworkEditor = true
                } label: {
                    PlaylistArtworkView(playlist: playlist, size: 112, cornerRadius: 24)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .purple)
                                .background(.black, in: Circle())
                                .offset(x: 6, y: 6)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Customize Playlist Artwork")
                .padding(.bottom, 8)
            }
            Text(playlist?.smartRule == nil ? "No tracks yet" : "No matching tracks")
                .font(.headline)
                .foregroundColor(.white)
            Text(playlist?.smartRule == nil
                 ? "Choose songs from your downloaded music."
                 : "This playlist will update when matching music is added.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            if playlist?.smartRule == nil {
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
        }
        .padding()
    }

    private var canManuallyEdit: Bool {
        playlist?.smartRule == nil
    }

    private var canReorder: Bool {
        canManuallyEdit &&
            sortOrder == .manual &&
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func orderIndex(_ track: Track) -> Int {
        tracks.firstIndex(of: track) ?? Int.max
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func removeTracks(at offsets: IndexSet) {
        guard let playlist else { return }
        for index in offsets where visibleTracks.indices.contains(index) {
            playlists.removeTrack(visibleTracks[index].id, from: playlist)
        }
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        guard let playlist else { return }
        playlists.moveTracks(
            in: playlist,
            resolvedTracks: visibleTracks,
            fromOffsets: source,
            toOffset: destination
        )
    }

    private func renamePlaylist() {
        guard let playlist else { return }
        playlists.rename(playlist, to: renamedName)
    }
}
