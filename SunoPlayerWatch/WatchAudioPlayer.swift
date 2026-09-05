import AVFoundation
import Foundation

@MainActor
final class WatchAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var currentTrack: WatchTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var lastError: String?

    private var player: AVAudioPlayer?
    private var queue: [WatchTrack] = []

    func play(_ track: WatchTrack, in tracks: [WatchTrack]) {
        queue = tracks
        Task { await start(track) }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            Task {
                guard await activateAudio() else { return }
                player.play()
                isPlaying = true
            }
        }
    }

    func next() {
        guard let currentTrack, let index = queue.firstIndex(of: currentTrack) else { return }
        let nextIndex = queue.index(after: index)
        guard nextIndex < queue.endIndex else { return }
        Task { await start(queue[nextIndex]) }
    }

    func previous() {
        guard let currentTrack, let index = queue.firstIndex(of: currentTrack), index > queue.startIndex else {
            player?.currentTime = 0
            return
        }
        Task { await start(queue[queue.index(before: index)]) }
    }

    func clearError() {
        lastError = nil
    }

    private func start(_ track: WatchTrack) async {
        guard await activateAudio() else { return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: track.fileURL)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            currentTrack = track
            isPlaying = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func activateAudio() async -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try await session.activate()
            return true
        } catch {
            lastError = "Connect Bluetooth headphones to play music."
            return false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if flag { next() } else { isPlaying = false }
        }
    }
}
