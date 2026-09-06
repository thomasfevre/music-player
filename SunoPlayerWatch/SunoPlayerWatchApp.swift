import SwiftUI

@main
struct SunoPlayerWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate
    @StateObject private var bridge = WatchBridge.shared
    @StateObject private var player = WatchAudioPlayer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    if let track = player.current {
                        Section("Now playing") {
                            Text(track.title).font(.headline)
                            Button {
                                if player.isPlaying { player.pause() } else { player.resume() }
                            } label: { Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") }
                        }
                    }
                    if bridge.tracks.isEmpty {
                        Section {
                            Label("Your music, offline", systemImage: "music.note")
                            Text("Open Watch Offline in the iPhone app to send music. Saved tracks play without your phone.")
                        }
                    } else {
                        Section("On this Watch · \(bridge.tracks.count)") {
                            ForEach(bridge.tracks) { track in
                                Button { player.play(track, at: bridge.audioURL(track)) } label: {
                                    VStack(alignment: .leading) {
                                        Text(track.title)
                                        if let artist = track.artist { Text(artist).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                    Section("Sync status") {
                        Text(bridge.status).font(.caption)
                        if let error = bridge.error ?? player.error { Text(error).foregroundStyle(.red) }
                        Button("Refresh status") { bridge.foreground() }
                    }
                }
                .navigationTitle("SunoPlayer")
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { bridge.foreground() } }
        }
    }
}
