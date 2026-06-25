import SwiftUI
import AVFoundation

@main
struct SunoPlayerApp: App {
    @StateObject private var library = MusicLibraryManager()
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var playlists = PlaylistManager()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(playlists)
                .preferredColorScheme(.dark)
        }
    }

    private func configureAudioSession() {
        do {
            // Configure the category at launch; activation is deferred to first playback
            // (AudioPlayerManager.activateSessionIfNeeded). `.allowBluetoothA2DP` only —
            // `.allowBluetooth` would route music through low-quality HFP on some devices.
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
        } catch {
            print("Audio session configuration failed: \(error)")
        }
    }
}
