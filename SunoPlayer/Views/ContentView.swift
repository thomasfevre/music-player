import SwiftUI

// MARK: - ContentView
/// Root view: library + floating mini player overlay.
struct ContentView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var playlists: PlaylistManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LibraryView(showNowPlaying: $showNowPlaying)

            // Mini Player — visible only when a track is loaded
            if player.currentTrack != nil {
                MiniPlayerView(showNowPlaying: $showNowPlaying)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: player.currentTrack != nil)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_SEED") {
                _ = player.listeningHistory.seedDemoHistory(for: library.tracks)
            }
            if ProcessInfo.processInfo.arguments.contains("UITEST_AUTOPLAY"),
               let first = library.displayedTracks.first {
                player.play(first, in: library.displayedTracks, source: .library)
                if ProcessInfo.processInfo.arguments.contains("UITEST_AUTODJ") {
                    _ = player.startAutoDJ(
                        library: library.tracks,
                        favoriteIDs: library.favoriteIDs,
                        playlistGroups: playlists.playlists.map {
                            PlaylistResolver.tracks(
                                for: $0,
                                in: library.tracks,
                                favoriteIDs: library.favoriteIDs
                            ).map(\.id)
                        }
                    )
                }
                showNowPlaying = true
                return
            }
            #endif
            // Restore the last session (paused) so the mini player reappears where we left off.
            player.restoreLastSession(in: library.tracks)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { WatchOfflineManager.shared.checkInventory() }
            if phase == .background || phase == .inactive {
                player.saveStateNow()
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView(isPresented: $showNowPlaying)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(playlists)
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { player.lastError != nil },
                set: { if !$0 { player.clearError() } }
            )
        ) {
            Button("OK") { player.clearError() }
        } message: {
            Text(player.lastError ?? "")
        }
        .background(Color.black.ignoresSafeArea())
    }
}
