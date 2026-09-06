import SwiftUI

struct SmartPlaylistEditorView: View {
    @EnvironmentObject var playlists: PlaylistManager
    @EnvironmentObject var library: MusicLibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: Kind = .genre
    @State private var value = ""
    @State private var recentDays = 30
    @State private var keepsUpdating = true

    let onCreate: (Playlist) -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case genre = "Genre"
        case artist = "Artist"
        case album = "Album"
        case favorites = "Favorites"
        case recentlyAdded = "Recently Added"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist") {
                    TextField("Name (optional)", text: $name)
                }
                Section("Automatically include") {
                    Picker("Rule", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if [.genre, .artist, .album].contains(kind) {
                        TextField("\(kind.rawValue) contains", text: $value)
                    } else if kind == .recentlyAdded {
                        Stepper("Last \(recentDays) days", value: $recentDays, in: 1...365)
                    }
                }
                Section {
                    Toggle("Keep this playlist updated", isOn: $keepsUpdating)
                    Text(
                        keepsUpdating
                            ? "This smart playlist updates automatically when your library or favorites change."
                            : "This creates a normal playlist with the tracks that match this rule right now."
                    )
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Smart Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(requiresValue && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var requiresValue: Bool {
        [.genre, .artist, .album].contains(kind)
    }

    private func create() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule: SmartPlaylistRule
        switch kind {
        case .genre: rule = .genre(trimmed)
        case .artist: rule = .artist(trimmed)
        case .album: rule = .album(trimmed)
        case .favorites: rule = .favorites
        case .recentlyAdded: rule = .recentlyAdded(days: recentDays)
        }
        let created: Playlist
        if keepsUpdating {
            created = playlists.createSmartPlaylist(name: name, rule: rule)
        } else {
            let matchingTrackIDs = library.tracks
                .filter { rule.matches($0, favoriteIDs: library.favoriteIDs) }
                .sorted { $0.dateImported > $1.dateImported }
                .map(\.id)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            created = playlists.createPlaylist(
                name: trimmedName.isEmpty ? rule.summary : trimmedName,
                trackIDs: matchingTrackIDs
            )
        }
        dismiss()
        onCreate(created)
    }
}
