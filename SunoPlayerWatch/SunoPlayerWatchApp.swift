import SwiftUI

@main
struct SunoPlayerWatchApp: App {
    @StateObject private var library = WatchLibrary()
    @StateObject private var player = WatchAudioPlayer()

    var body: some Scene {
        WindowGroup {
            WatchLibraryView()
                .environmentObject(library)
                .environmentObject(player)
        }
        .backgroundTask(.watchConnectivity) {
            // WatchLibrary owns the WCSession delegate and synchronously stores files.
        }
    }
}
