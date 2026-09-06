import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class WatchAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var current: OfflineTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?
    private var player: AVAudioPlayer?
    private var interruption: NSObjectProtocol?
    private var routeChange: NSObjectProtocol?
    private var activationID = UUID()

    override init() {
        super.init()
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
        routeChange = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.pause() }
        }
        MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
    }

    func play(_ track: OfflineTrack, at url: URL) {
        do {
            pause()
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            player = audio
            current = track
            error = nil
            resume()
        } catch { self.error = error.localizedDescription }
    }

    func resume() {
        guard player != nil else { return }
        let activation = UUID()
        activationID = activation
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            // watchOS may present the route picker when no Bluetooth route is available.
            session.activate(options: []) { [weak self] success, failure in
                Task { @MainActor in
                    guard let self, self.activationID == activation, let player = self.player else { return }
                    if success { self.isPlaying = player.play(); self.updateNowPlaying() }
                    else { self.error = failure?.localizedDescription ?? "Connect audio output to play music." }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func pause() { activationID = UUID(); player?.pause(); isPlaying = false; updateNowPlaying() }

    private func updateNowPlaying() {
        guard let current, let player else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist ?? "Unknown Artist",
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in isPlaying = false; updateNowPlaying() }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.error = error?.localizedDescription ?? "Audio could not be decoded."; isPlaying = false }
    }
}
