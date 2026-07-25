import SwiftUI

struct QueueView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var playlists: PlaylistManager
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveAlert = false
    @State private var playlistName = "Saved Queue"

    private var upcoming: [Track] {
        guard let current = player.currentTrack,
              let index = player.activeQueue.firstIndex(of: current),
              index + 1 < player.activeQueue.count else { return [] }
        return Array(player.activeQueue[(index + 1)...])
    }

    var body: some View {
        NavigationStack {
            List {
                if let current = player.currentTrack {
                    Section("Now Playing") {
                        queueRow(current, isCurrent: true)
                    }
                }
                Section("Up Next") {
                    if upcoming.isEmpty {
                        Text("Nothing else is queued.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcoming) { queueRow($0, isCurrent: false) }
                            .onMove(perform: player.moveUpcoming)
                            .onDelete(perform: player.removeUpcoming)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .disabled(upcoming.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            playlistName = "Saved Queue"
                            showSaveAlert = true
                        } label: {
                            Label("Save Queue as Playlist", systemImage: "music.note.list")
                        }
                        .disabled(player.activeQueue.isEmpty)
                        Button(role: .destructive) {
                            player.clearUpcoming()
                        } label: {
                            Label("Clear Up Next", systemImage: "trash")
                        }
                        .disabled(upcoming.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Save Queue as Playlist", isPresented: $showSaveAlert) {
                TextField("Playlist name", text: $playlistName)
                Button("Cancel", role: .cancel) {}
                Button("Save", action: saveQueue)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func queueRow(_ track: Track, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(track.title)
                if isCurrent {
                    Spacer()
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.purple)
                }
            }
            Text(track.displayArtist)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func saveQueue() {
        let created = playlists.createPlaylist(name: playlistName)
        playlists.addTracks(player.activeQueue.map(\.id), to: created)
    }
}
