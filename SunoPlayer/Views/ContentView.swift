import SwiftUI

// MARK: - ContentView
/// Root view: library + floating mini player overlay.
struct ContentView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager

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
            if ProcessInfo.processInfo.arguments.contains("UITEST_AUTOPLAY"),
               let first = library.displayedTracks.first {
                player.play(first, in: library.displayedTracks)
                showNowPlaying = true
            }
            #endif
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(isPresented: $showNowPlaying)
                .environmentObject(library)
                .environmentObject(player)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
