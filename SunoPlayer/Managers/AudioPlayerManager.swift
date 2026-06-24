import Foundation
import AVFoundation
import MediaPlayer
import Combine

// MARK: - AudioPlayerManager
/// Controls audio playback, queue management, shuffle, repeat, and Now Playing info.
/// `@MainActor`-isolated: every `@Published` mutation happens on the main thread, and all
/// AVFoundation / remote-command / audio-session callbacks hop back to the main actor.
@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {

    // MARK: Published State
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastError: String?
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    // MARK: Private
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var queue = PlaybackQueue()
    private var wasPlayingBeforeInterruption = false

    /// Observers tied to the current item (replaced every load).
    private var itemObservers: [NSObjectProtocol] = []
    /// Observers tied to the manager's lifetime (audio-session events).
    private var sessionObservers: [NSObjectProtocol] = []
    /// Remote-command targets, retained so they can be removed in `deinit`.
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    // MARK: Computed
    var activeQueue: [Track] { queue.activeOrder }

    // MARK: Init
    override init() {
        super.init()
        setupRemoteControls()
        setupAudioSessionObservers()
    }

    deinit {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        itemStatusObservation?.invalidate()
        itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        for (command, token) in remoteTargets { command.removeTarget(token) }
    }

    // MARK: - Playback Control

    /// Load a track from a given queue and start playing.
    func play(_ track: Track, in newQueue: [Track]) {
        queue.repeatMode = repeatMode
        if queue.shuffleEnabled != shuffleEnabled {
            queue.setShuffle(shuffleEnabled)
        }
        queue.setQueue(newQueue, startAt: track)
        guard let current = queue.currentTrack else { return }
        loadAndPlay(track: current)
    }

    func playPause() {
        guard player != nil else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            guard activateSession() else { updateNowPlayingPlaybackState(); return }
            player?.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackState()
    }

    func next() {
        guard !queue.isEmpty else { return }
        queue.repeatMode = repeatMode
        if repeatMode == .one {
            guard player != nil else { return }   // nothing loaded — never claim "playing"
            seek(to: 0)
            if activateSession() {
                player?.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
            updateNowPlayingPlaybackState()
            return
        }
        if let index = queue.next(), let track = queue.track(at: index) {
            loadAndPlay(track: track)
        } else {
            // End of queue with repeat off.
            player?.pause()
            isPlaying = false
            updateNowPlayingPlaybackState()
        }
    }

    func previous() {
        switch queue.previous(currentTime: currentTime) {
        case .restart:
            seek(to: 0)
        case .play(let index):
            if let track = queue.track(at: index) { loadAndPlay(track: track) }
        case .none:
            break
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingInfo()
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        queue.setShuffle(shuffleEnabled)
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        queue.repeatMode = repeatMode
    }

    /// Coordinate with a track deletion. If the deleted track is currently playing,
    /// playback stops and the selection clears; otherwise the queue is just trimmed.
    func handleTrackDeleted(_ track: Track) {
        let wasCurrent = queue.remove(track)
        if wasCurrent {
            clearPlayback()
        }
    }

    // MARK: - Internal Playback

    private func loadAndPlay(track: Track) {
        tearDownCurrentItem()

        guard FileManager.default.fileExists(atPath: track.fileURL.path) else {
            handlePlaybackFailure("Audio file is missing: \(track.title)")
            return
        }

        lastError = nil
        let sessionActive = activateSession()
        currentTrack = track
        duration = track.duration
        currentTime = 0

        let item = AVPlayerItem(url: track.fileURL)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        // Item-scoped observers. The identity guard (`item === player?.currentItem`)
        // ensures a delayed failure from an obsolete item cannot tear down a newer one.
        let endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, item === self.player?.currentItem else { return }
                self.next()
            }
        }
        let failObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "Playback failed"
            MainActor.assumeIsolated {
                guard let self, item === self.player?.currentItem else { return }
                self.handlePlaybackFailure(message)
            }
        }
        itemObservers = [endObs, failObs]

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            let message = observedItem.error?.localizedDescription ?? "This track could not be loaded"
            Task { @MainActor in
                guard let self, observedItem === self.player?.currentItem else { return }
                self.handlePlaybackFailure(message)
            }
        }

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if let loaded = self.player?.currentItem?.duration, loaded.isNumeric {
                    self.duration = loaded.seconds
                }
            }
        }

        if sessionActive {
            newPlayer.play()
            isPlaying = true
        } else {
            // Couldn't activate the audio session — don't report a misleading "playing" state.
            isPlaying = false
        }
        updateNowPlayingInfo()
    }

    private func tearDownCurrentItem() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        itemObservers.removeAll()
        player?.pause()
        player = nil
    }

    /// Centralized failure handling for both pre-load (missing file) and async item failures.
    private func handlePlaybackFailure(_ message: String) {
        tearDownCurrentItem()
        isPlaying = false
        currentTime = 0
        duration = 0
        currentTrack = nil
        lastError = message
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Stop playback and clear selection without recording an error (e.g. current track deleted).
    private func clearPlayback() {
        tearDownCurrentItem()
        isPlaying = false
        currentTime = 0
        duration = 0
        currentTrack = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Activates the shared audio session. Always calls `setActive(true)` (no cached flag), so
    /// playback reliably reactivates after an interruption deactivated the session. Returns
    /// whether activation succeeded so callers don't report a misleading "playing" state.
    @discardableResult
    private func activateSession() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            return true
        } catch {
            lastError = "Audio session activation failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Audio Session Lifecycle

    private func setupAudioSessionObservers() {
        let center = NotificationCenter.default
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        }
        let route = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleRouteChange(note) }
        }
        sessionObservers = [interruption, route]
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                player?.pause()
                isPlaying = false
                updateNowPlayingPlaybackState()
            }
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            if AudioInterruptionPolicy.shouldResume(wasPlaying: wasPlayingBeforeInterruption, options: options),
               player != nil,                      // playback may have been cleared mid-interruption
               activateSession() {
                player?.play()
                isPlaying = true
                updateNowPlayingPlaybackState()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        if AudioRoutePolicy.shouldPause(reason: reason), isPlaying {
            player?.pause()
            isPlaying = false
            updateNowPlayingPlaybackState()
        }
    }

    // MARK: - Now Playing / Remote Controls

    /// Runs main-actor work from a callback that has no executor guarantee
    /// (MPRemoteCommand handlers are not promised on the main thread). Synchronous when
    /// already on main; otherwise hops. Avoids `assumeIsolated` trapping off-main.
    private nonisolated func onMain(_ work: @MainActor @escaping () -> Void) {
        // Always dispatch onto the main queue, which IS the main actor's executor — so
        // assumeIsolated can never trap. (Being on the main *thread* alone wouldn't guarantee
        // main-actor executor context.)
        DispatchQueue.main.async { MainActor.assumeIsolated(work) }
    }

    private func setupRemoteControls() {
        let center = MPRemoteCommandCenter.shared()

        let play = center.playCommand.addTarget { [weak self] _ in
            self?.onMain {
                guard let self, self.player != nil, self.activateSession() else { return }
                self.player?.play()
                self.isPlaying = true
                self.updateNowPlayingPlaybackState()
            }
            return .success
        }
        let pause = center.pauseCommand.addTarget { [weak self] _ in
            self?.onMain {
                guard let self, self.player != nil else { return }
                self.player?.pause()
                self.isPlaying = false
                self.updateNowPlayingPlaybackState()
            }
            return .success
        }
        let nextCmd = center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onMain {
                guard let self, !self.queue.isEmpty else { return }
                self.next()
            }
            return .success
        }
        let prevCmd = center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onMain {
                guard let self, !self.queue.isEmpty else { return }
                self.previous()
            }
            return .success
        }
        let seekCmd = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.onMain {
                guard let self, self.player != nil else { return }
                self.seek(to: e.positionTime)
            }
            return .success
        }

        remoteTargets = [
            (center.playCommand, play),
            (center.pauseCommand, pause),
            (center.nextTrackCommand, nextCmd),
            (center.previousTrackCommand, prevCmd),
            (center.changePlaybackPositionCommand, seekCmd)
        ]
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard currentTrack != nil else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
