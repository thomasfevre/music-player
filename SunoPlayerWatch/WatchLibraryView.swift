import SwiftUI

struct WatchLibraryView: View {
    @EnvironmentObject private var library: WatchLibrary
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    ContentUnavailableView(
                        "No Music",
                        systemImage: "applewatch.radiowaves.left.and.right",
                        description: Text("Send tracks from Music Player on your iPhone.")
                    )
                } else {
                    List {
                        if let current = player.current {
                            NavigationLink {
                                WatchNowPlayingView()
                            } label: {
                                Label(current.title, systemImage: "waveform")
                                    .lineLimit(1)
                            }
                            .listRowBackground(Color.purple.opacity(0.22))
                        }

                        ForEach(library.tracks) { track in
                            Button {
                                    player.play(track, at: track.fileURL)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).lineLimit(1)
                                    Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete(perform: library.delete)

                        Section {
                            LabeledContent("On Watch") {
                                Text(ByteCountFormatter.string(
                                    fromByteCount: library.storageBytes,
                                    countStyle: .file
                                ))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Music Player", isPresented: Binding(
                get: { library.lastError != nil || player.error != nil },
                set: { if !$0 { clearErrors() } }
            )) {
                Button("OK", action: clearErrors)
            } message: {
                Text(library.lastError ?? player.error ?? "")
            }
        }
    }

    private func clearErrors() {
        library.clearError()
    }
}

struct WatchNowPlayingView: View {
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.largeTitle)
                .frame(width: 62, height: 62)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            Text(player.current?.title ?? "Not Playing")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(player.current?.artist ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 20) {
                Button(action: player.pause) { Image(systemName: "backward.fill") }
                Button(action: { player.isPlaying ? player.pause() : player.resume() }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: player.resume) { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.plain)
            .font(.title3)
        }
        .navigationTitle("Now Playing")
    }
}
