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
    @Published private(set) var activeQueue: [Track] = []
    @Published private(set) var autoDJSession: AutoDJSession?
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    /// Seconds left on the sleep timer, or nil when it's off.
    @Published private(set) var sleepTimerRemaining: TimeInterval?

    /// Current playback rate (1.0 = normal). Applied to the player and Now Playing info.
    @Published private(set) var playbackRate: Float = PlaybackSpeed.default

    // MARK: Private
    private var player: AVPlayer?
    private var fadingOutPlayer: AVPlayer?
    private var crossfadeCancellable: AnyCancellable?
    private var pendingCrossfadeDuration: TimeInterval?
    private var crossfadeStartedForCurrentItem = false
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var queue = PlaybackQueue()
    private var manuallyQueuedTrackIDs: Set<UUID> = []
    private var playbackObservation: PlaybackObservation?
    private var wasPlayingBeforeInterruption = false
    private var sleepCancellable: AnyCancellable?
    /// Position to seek to once the current item reaches `.readyToPlay` (resume restore).
    private var pendingSeek: TimeInterval?
    private let playbackStateKey = "lastPlayback"
    /// currentTime at the last persistence write, to throttle disk writes during playback.
    private var lastPersistedTime: TimeInterval = 0

    /// Observers tied to the current item (replaced every load).
    private var itemObservers: [NSObjectProtocol] = []
    /// Observers tied to the manager's lifetime (audio-session events).
    private var sessionObservers: [NSObjectProtocol] = []
    /// Remote-command targets, retained so they can be removed in `deinit`.
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    let listeningHistory: ListeningHistoryStore

    private struct PlaybackObservation {
        let trackID: UUID
        let previousTrackID: UUID?
        let source: PlaybackSource
        let startedAt: Date
        var listenedSeconds: TimeInterval
        var lastPosition: TimeInterval
        let wasReplay: Bool
    }

    // MARK: Init
    override init() {
        listeningHistory = ListeningHistoryStore()
        super.init()
        lastError = listeningHistory.lastError
        setupRemoteControls()
        setupAudioSessionObservers()
    }

    init(listeningHistory: ListeningHistoryStore) {
        self.listeningHistory = listeningHistory
        super.init()
        lastError = listeningHistory.lastError
        setupRemoteControls()
        setupAudioSessionObservers()
    }

    deinit {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        itemStatusObservation?.invalidate()
        itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        for (command, token) in remoteTargets { command.removeTarget(token) }
        sleepCancellable?.cancel()
        crossfadeCancellable?.cancel()
        fadingOutPlayer?.pause()
    }

    // MARK: - Playback Control

    /// Load a track from a given queue and start playing.
    func play(
        _ track: Track,
        in newQueue: [Track],
        source: PlaybackSource = .library
    ) {
        let shouldCrossfade = isPlaying
        finalizePlayback(reason: .replacedBySelection)
        stopAutoDJ()
        manuallyQueuedTrackIDs.removeAll()
        queue.repeatMode = repeatMode
        if queue.shuffleEnabled != shuffleEnabled {
            queue.setShuffle(shuffleEnabled)
        }
        queue.setQueue(newQueue, startAt: track)
        syncQueue()
        guard let current = queue.currentTrack else { return }
        loadAndPlay(track: current, source: source, crossfade: shouldCrossfade)
    }

    func playPause() {
        guard player != nil else { return }
        if isPlaying {
            pausePlayback()
            persistPlayback()
        } else {
            guard activateSession() else { updateNowPlayingPlaybackState(); return }
            player?.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackState()
    }

    func next() {
        advance(reason: .manualSkip)
    }

    private func advance(reason: ListeningEndReason, crossfadeDuration: TimeInterval? = nil) {
        guard !queue.isEmpty else { return }
        let previousTrackID = currentTrack?.id
        finalizePlayback(
            reason: reason,
            additionalListenedSeconds: reason == .naturalCompletion ? crossfadeDuration ?? 0 : 0
        )
        queue.repeatMode = repeatMode
        if repeatMode == .one {
            guard player != nil else { return }   // nothing loaded — never claim "playing"
            seek(to: 0)
            if let currentTrack {
                beginPlaybackObservation(
                    track: currentTrack,
                    previousTrackID: previousTrackID,
                    source: autoDJSession == nil ? .queue : .autoDJ,
                    wasReplay: true
                )
            }
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
            manuallyQueuedTrackIDs.remove(track.id)
            let recommendation = autoDJSession?.recommendationsByTrackID[track.id]
            let source: PlaybackSource = recommendation == nil
                ? .queue
                : .autoDJ
            autoDJSession?.playedTrackIDs.insert(track.id)
            autoDJSession?.currentRecommendation = recommendation
            autoDJSession?.recommendationsByTrackID.removeValue(forKey: track.id)
            syncQueue()
            loadAndPlay(
                track: track,
                source: source,
                previousTrackID: previousTrackID,
                crossfade: reason == .naturalCompletion || reason == .manualSkip,
                crossfadeDuration: crossfadeDuration
            )
            replenishAutoDJQueue()
        } else {
            // End of queue with repeat off.
            stopAutoDJ()
            pausePlayback()
        }
    }

    func previous() {
        switch queue.previous(currentTime: currentTime) {
        case .restart:
            finalizePlayback(reason: .previous)
            seek(to: 0)
            if let currentTrack {
                beginPlaybackObservation(
                    track: currentTrack,
                    previousTrackID: nil,
                    source: autoDJSession == nil ? .queue : .autoDJ,
                    wasReplay: true
                )
            }
        case .play(let index):
            let previousTrackID = currentTrack?.id
            finalizePlayback(reason: .previous)
            autoDJSession?.currentRecommendation = nil
            syncQueue()
            if let track = queue.track(at: index) {
                autoDJSession?.playedTrackIDs.insert(track.id)
                loadAndPlay(
                    track: track,
                    source: .queue,
                    previousTrackID: previousTrackID,
                    crossfade: isPlaying
                )
            }
        case .none:
            break
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        playbackObservation?.lastPosition = time
        updateNowPlayingInfo()
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        queue.setShuffle(shuffleEnabled)
        syncQueue()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        queue.repeatMode = repeatMode
    }

    /// Coordinate with a track deletion. If the deleted track is currently playing,
    /// playback stops and the selection clears; otherwise the queue is just trimmed.
    func handleTrackDeleted(_ track: Track) {
        let deletingCurrentTrack = currentTrack == track
        if deletingCurrentTrack {
            finalizePlayback(reason: .deleted)
        }
        removeListeningHistory(for: track.id)
        manuallyQueuedTrackIDs.remove(track.id)
        autoDJSession?.excludedTrackIDs.insert(track.id)
        autoDJSession?.recommendationsByTrackID.removeValue(forKey: track.id)
        let wasCurrent = queue.remove(track)
        syncQueue()
        if wasCurrent {
            stopAutoDJ()
            queue = PlaybackQueue()
            queue.repeatMode = repeatMode
            if shuffleEnabled { queue.setShuffle(true) }
            syncQueue()
            clearPlayback()
        }
    }

    func enqueueNext(_ track: Track) {
        guard currentTrack != nil else {
            play(track, in: [track], source: .queue)
            return
        }
        guard currentTrack?.id != track.id else { return }
        manuallyQueuedTrackIDs.insert(track.id)
        autoDJSession?.recommendationsByTrackID.removeValue(forKey: track.id)
        queue.enqueueNext(track)
        recordListeningEvent(.action(
            trackID: track.id,
            relatedTrackID: currentTrack?.id,
            kind: .queuedNext,
            at: Date()
        ))
        syncQueue()
    }

    func enqueueLater(_ track: Track) {
        guard currentTrack != nil else {
            play(track, in: [track], source: .queue)
            return
        }
        guard currentTrack?.id != track.id else { return }
        manuallyQueuedTrackIDs.insert(track.id)
        autoDJSession?.recommendationsByTrackID.removeValue(forKey: track.id)
        if autoDJSession != nil {
            // Deduplicate against both playback history and upcoming suggestions before
            // promoting this explicit request ahead of automatic recommendations.
            queue.enqueueLater(track)
            let remaining = queue.upcomingTracks.filter { $0.id != track.id }
            let manual = remaining.filter { manuallyQueuedTrackIDs.contains($0.id) }
            let automatic = remaining.filter { !manuallyQueuedTrackIDs.contains($0.id) }
            queue.replaceUpcoming(with: manual + [track] + automatic)
        } else {
            queue.enqueueLater(track)
        }
        recordListeningEvent(.action(
            trackID: track.id,
            relatedTrackID: currentTrack?.id,
            kind: .queuedLater,
            at: Date()
        ))
        syncQueue()
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpcoming(fromOffsets: source, toOffset: destination)
        syncQueue()
    }

    func removeUpcoming(at offsets: IndexSet) {
        let removed = offsets.compactMap {
            queue.upcomingTracks.indices.contains($0) ? queue.upcomingTracks[$0] : nil
        }
        queue.removeUpcoming(at: offsets)
        let events = removed.map {
            ListeningEvent.action(
                trackID: $0.id,
                relatedTrackID: currentTrack?.id,
                kind: .removedFromQueue,
                at: Date()
            )
        }
        for track in removed {
            manuallyQueuedTrackIDs.remove(track.id)
            if autoDJSession?.recommendationsByTrackID[track.id] != nil {
                autoDJSession?.excludedTrackIDs.insert(track.id)
            }
            autoDJSession?.recommendationsByTrackID.removeValue(forKey: track.id)
        }
        recordListeningEvents(events)
        syncQueue()
        replenishAutoDJQueue()
    }

    func clearUpcoming() {
        let removed = queue.upcomingTracks
        queue.clearUpcoming()
        let events = removed.map {
            ListeningEvent.action(
                trackID: $0.id,
                relatedTrackID: currentTrack?.id,
                kind: .removedFromQueue,
                at: Date()
            )
        }
        for track in removed {
            manuallyQueuedTrackIDs.remove(track.id)
            autoDJSession?.recommendationsByTrackID.removeValue(forKey: track.id)
        }
        recordListeningEvents(events)
        stopAutoDJ()
        syncQueue()
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Auto-DJ

    var isAutoDJEnabled: Bool {
        autoDJSession != nil
    }

    var autoDJUpcomingRecommendations: [AutoDJRecommendation] {
        guard let autoDJSession else { return [] }
        return queue.upcomingTracks.compactMap {
            autoDJSession.recommendationsByTrackID[$0.id]
        }
    }

    var currentAutoDJReason: String? {
        autoDJSession?.currentRecommendation?.reasonText
    }

    @discardableResult
    func startAutoDJ(
        library: [Track],
        favoriteIDs: Set<UUID>,
        playlistGroups: [[UUID]]
    ) -> Bool {
        guard currentTrack != nil, library.count > 1 else { return false }

        let manualTracks = queue.upcomingTracks.filter {
            manuallyQueuedTrackIDs.contains($0.id)
        }
        queue.clearUpcoming()
        for track in manualTracks {
            queue.enqueueLater(track)
        }

        var session = AutoDJSession(
            library: library,
            favoriteIDs: favoriteIDs,
            playlistGroups: playlistGroups
        )
        if let currentTrack {
            session.playedTrackIDs.insert(currentTrack.id)
        }
        autoDJSession = session
        syncQueue()
        replenishAutoDJQueue()
        return !queue.upcomingTracks.isEmpty
    }

    func stopAutoDJ() {
        guard let session = autoDJSession else { return }
        let manualTracks = queue.upcomingTracks.filter {
            manuallyQueuedTrackIDs.contains($0.id) &&
            session.recommendationsByTrackID[$0.id] == nil
        }
        queue.clearUpcoming()
        for track in manualTracks {
            queue.enqueueLater(track)
        }
        autoDJSession = nil
        syncQueue()
    }

    func submitAutoDJFeedback(positive: Bool) {
        guard isAutoDJEnabled, let currentTrack else { return }
        recordListeningEvent(.feedback(
            trackID: currentTrack.id,
            previousTrackID: playbackObservation?.previousTrackID,
            positive: positive,
            at: Date()
        ))

        if positive {
            if autoDJSession?.preferredTracks.contains(where: { $0.id == currentTrack.id }) == false {
                autoDJSession?.preferredTracks.append(currentTrack)
            }
            rebuildAutoDJRecommendations()
        } else {
            autoDJSession?.excludedTrackIDs.insert(currentTrack.id)
            advance(reason: .manualSkip)
        }
    }

    func recordFavoriteChange(for trackID: UUID, isFavorite: Bool) {
        recordListeningEvent(.action(
            trackID: trackID,
            kind: isFavorite ? .favoriteAdded : .favoriteRemoved,
            at: Date()
        ))
        if isFavorite {
            autoDJSession?.favoriteIDs.insert(trackID)
        } else {
            autoDJSession?.favoriteIDs.remove(trackID)
        }
    }

    func resetListeningHistory() {
        if listeningHistory.reset() {
            stopAutoDJ()
        } else {
            lastError = listeningHistory.lastError
        }
    }

    // MARK: - Resume Last Session

    /// Restores the last played track (paused, at its saved position) if it still exists.
    /// Call once at launch after the library has loaded. No-op if nothing is loaded yet
    /// or there is no valid snapshot.
    func restoreLastSession(in tracks: [Track]) {
        guard currentTrack == nil,
              let restore = PlaybackRestore.resolve(loadPersistedPlayback(), in: tracks) else { return }
        queue.repeatMode = repeatMode
        queue.setQueue(tracks, startAt: restore.track)
        syncQueue()
        loadAndPlay(
            track: restore.track,
            autoPlay: false,
            startAt: restore.position,
            source: .restored
        )
    }

    /// Persist immediately (e.g. when the app moves to the background).
    func saveStateNow() {
        persistPlayback()
    }

    // MARK: - Sleep Timer

    /// Starts (or restarts) a sleep timer that pauses playback after `minutes`.
    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepTimerRemaining = TimeInterval(minutes * 60)
        sleepCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Route through onMain (DispatchQueue.main → main-actor executor) rather than
                // assumeIsolated directly: a RunLoop timer fires on the main *thread* but not
                // necessarily inside the main-actor executor context.
                self?.onMain {
                    guard let self, let remaining = self.sleepTimerRemaining else { return }
                    let tick = SleepTimer.advance(remaining: remaining)
                    if tick.fired {
                        self.cancelSleepTimer()
                        if self.isPlaying { self.playPause() }
                    } else {
                        self.sleepTimerRemaining = tick.next
                    }
                }
            }
    }

    func cancelSleepTimer() {
        sleepCancellable?.cancel()
        sleepCancellable = nil
        sleepTimerRemaining = nil
    }

    // MARK: - Playback Speed

    /// Sets the playback rate. Uses `defaultRate` so it sticks across future `play()` calls,
    /// and applies live if currently playing.
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.defaultRate = rate
        if isPlaying { player?.rate = rate }
        updateNowPlayingPlaybackState()
    }

    // MARK: - Persistence

    private func persistPlayback() {
        guard let track = currentTrack else { return }
        lastPersistedTime = currentTime
        let state = PersistedPlayback(trackID: track.id, position: currentTime)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: playbackStateKey)
        }
    }

    private func loadPersistedPlayback() -> PersistedPlayback? {
        guard let data = UserDefaults.standard.data(forKey: playbackStateKey) else { return nil }
        return try? JSONDecoder().decode(PersistedPlayback.self, from: data)
    }

    private func clearPersistedPlayback() {
        UserDefaults.standard.removeObject(forKey: playbackStateKey)
    }

    // MARK: - Internal Playback

    /// - Parameters:
    ///   - autoPlay: when false, the item loads paused (used to restore the last session at
    ///     launch without grabbing the audio session from other apps).
    ///   - startAt: position to seek to once loaded (used for resume).
    private func loadAndPlay(
        track: Track,
        autoPlay: Bool = true,
        startAt: TimeInterval = 0,
        source: PlaybackSource = .queue,
        previousTrackID: UUID? = nil,
        wasReplay: Bool = false,
        crossfade: Bool = false,
        crossfadeDuration: TimeInterval? = nil
    ) {
        let configuredCrossfade = min(
            PlaybackPreferences.crossfadeDuration,
            crossfadeDuration ?? PlaybackPreferences.crossfadeDuration
        )
        let shouldCrossfade = crossfade && isPlaying && configuredCrossfade > 0
        let outgoingPlayer = tearDownCurrentItem(keepPlaying: shouldCrossfade)
        if shouldCrossfade {
            fadingOutPlayer = outgoingPlayer
            pendingCrossfadeDuration = configuredCrossfade
        }

        guard FileManager.default.fileExists(atPath: track.fileURL.path) else {
            handlePlaybackFailure("Audio file is missing: \(track.title)")
            return
        }

        lastError = nil
        // Only claim the audio session when we actually intend to play now.
        let sessionActive = autoPlay ? activateSession() : false
        currentTrack = track
        duration = track.duration
        currentTime = startAt
        lastPersistedTime = startAt
        beginPlaybackObservation(
            track: track,
            previousTrackID: previousTrackID,
            source: source,
            wasReplay: wasReplay,
            startingAt: startAt
        )

        let item = AVPlayerItem(url: track.fileURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.defaultRate = playbackRate   // play() honors this rate
        newPlayer.volume = shouldCrossfade ? 0 : 1
        player = newPlayer
        crossfadeStartedForCurrentItem = false

        // Defer the resume seek until the item is ready; seeking an unknown-status item can
        // silently no-op, leaving playback at 0 while the UI shows the restored position.
        pendingSeek = startAt > 0 ? startAt : nil

        // Item-scoped observers. The identity guard (`item === player?.currentItem`)
        // ensures a delayed failure from an obsolete item cannot tear down a newer one.
        let endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, item === self.player?.currentItem else { return }
                self.advance(reason: .naturalCompletion)
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
            switch observedItem.status {
            case .readyToPlay:
                Task { @MainActor in
                    guard let self, observedItem === self.player?.currentItem else { return }
                    if let target = self.pendingSeek {
                        self.pendingSeek = nil
                        // Clamp against the real duration now that it's known, guarding corrupted saves.
                        let realDuration = observedItem.duration.isNumeric ? observedItem.duration.seconds : self.duration
                        let clamped = realDuration > 0 ? min(target, realDuration) : target
                        self.player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 1000),
                                          toleranceBefore: .zero, toleranceAfter: .zero)
                        self.currentTime = clamped
                        self.updateNowPlayingInfo()
                    }
                    self.startPendingCrossfadeIfNeeded()
                }
            case .failed:
                let message = observedItem.error?.localizedDescription ?? "This track could not be loaded"
                Task { @MainActor in
                    guard let self, observedItem === self.player?.currentItem else { return }
                    self.handlePlaybackFailure(message)
                }
            default:
                break
            }
        }

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                self.updateListenedTime(position: time.seconds)
                if let loaded = self.player?.currentItem?.duration, loaded.isNumeric {
                    self.duration = loaded.seconds
                }
                // Throttled crash-safety persistence (every ~5s of playback).
                if self.isPlaying, abs(self.currentTime - self.lastPersistedTime) >= 5 {
                    self.persistPlayback()
                }
                let crossfadeLead = CrossfadePolicy.transitionLeadTime(
                    duration: self.duration,
                    configured: PlaybackPreferences.crossfadeDuration
                )
                if self.isPlaying, CrossfadePolicy.shouldBegin(
                    position: self.currentTime,
                    duration: self.duration,
                    configured: PlaybackPreferences.crossfadeDuration,
                    hasNextTrack: !self.queue.upcomingTracks.isEmpty || self.repeatMode == .all,
                    alreadyStarted: self.crossfadeStartedForCurrentItem
                ) {
                    self.crossfadeStartedForCurrentItem = true
                    self.advance(reason: .naturalCompletion, crossfadeDuration: crossfadeLead)
                }
            }
        }

        if autoPlay && sessionActive {
            newPlayer.play()
            isPlaying = true
        } else {
            // Couldn't activate the session, or restoring paused — don't claim "playing".
            isPlaying = false
        }
        updateNowPlayingInfo()
        persistPlayback()
    }

    @discardableResult
    private func tearDownCurrentItem(keepPlaying: Bool = false) -> AVPlayer? {
        crossfadeCancellable?.cancel()
        crossfadeCancellable = nil
        pendingCrossfadeDuration = nil
        fadingOutPlayer?.pause()
        fadingOutPlayer = nil

        let outgoingPlayer = player
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        itemObservers.removeAll()
        pendingSeek = nil
        if !keepPlaying { outgoingPlayer?.pause() }
        player = nil
        return outgoingPlayer
    }

    private func startCrossfade(from outgoing: AVPlayer, to incoming: AVPlayer, duration: TimeInterval) {
        crossfadeCancellable?.cancel()
        if fadingOutPlayer !== outgoing {
            fadingOutPlayer?.pause()
        }
        fadingOutPlayer = outgoing

        let startedAt = Date()
        crossfadeCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self, weak incoming, weak outgoing] _ in
                MainActor.assumeIsolated {
                    guard let self, let incoming, let outgoing else { return }
                    let progress = min(1, Date().timeIntervalSince(startedAt) / max(0.1, duration))
                    incoming.volume = Float(progress)
                    outgoing.volume = Float(1 - progress)
                    if progress >= 1 {
                        outgoing.pause()
                        self.fadingOutPlayer = nil
                        self.crossfadeCancellable?.cancel()
                        self.crossfadeCancellable = nil
                    }
                }
            }
    }

    private func startPendingCrossfadeIfNeeded() {
        guard let outgoing = fadingOutPlayer,
              let incoming = player,
              let duration = pendingCrossfadeDuration else { return }
        pendingCrossfadeDuration = nil
        startCrossfade(from: outgoing, to: incoming, duration: duration)
    }

    private func finishCrossfadeImmediately() {
        crossfadeCancellable?.cancel()
        crossfadeCancellable = nil
        pendingCrossfadeDuration = nil
        fadingOutPlayer?.pause()
        fadingOutPlayer = nil
        player?.volume = 1
    }

    private func pausePlayback() {
        finishCrossfadeImmediately()
        player?.pause()
        isPlaying = false
        updateNowPlayingPlaybackState()
    }

    /// Centralized failure handling for both pre-load (missing file) and async item failures.
    private func handlePlaybackFailure(_ message: String) {
        finalizePlayback(reason: .failed)
        stopAutoDJ()
        tearDownCurrentItem()
        isPlaying = false
        currentTime = 0
        duration = 0
        currentTrack = nil
        lastError = message
        clearPersistedPlayback()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Stop playback and clear selection without recording an error (e.g. current track deleted).
    private func clearPlayback() {
        tearDownCurrentItem()
        isPlaying = false
        currentTime = 0
        duration = 0
        currentTrack = nil
        clearPersistedPlayback()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func beginPlaybackObservation(
        track: Track,
        previousTrackID: UUID?,
        source: PlaybackSource,
        wasReplay: Bool,
        startingAt: TimeInterval = 0
    ) {
        playbackObservation = PlaybackObservation(
            trackID: track.id,
            previousTrackID: previousTrackID,
            source: source,
            startedAt: Date(),
            listenedSeconds: 0,
            lastPosition: startingAt,
            wasReplay: wasReplay
        )
    }

    private func updateListenedTime(position: TimeInterval) {
        guard isPlaying, var observation = playbackObservation else { return }
        let delta = position - observation.lastPosition
        if delta > 0, delta <= 2 {
            observation.listenedSeconds += delta
        }
        observation.lastPosition = position
        playbackObservation = observation
    }

    private func finalizePlayback(
        reason: ListeningEndReason,
        additionalListenedSeconds: TimeInterval = 0
    ) {
        guard let observation = playbackObservation else { return }
        playbackObservation = nil
        recordListeningEvent(.playback(
            trackID: observation.trackID,
            previousTrackID: observation.previousTrackID,
            source: observation.source,
            startedAt: observation.startedAt,
            endedAt: Date(),
            listenedSeconds: observation.listenedSeconds + additionalListenedSeconds,
            duration: duration,
            endReason: reason,
            wasReplay: observation.wasReplay
        ))
    }

    private func recordListeningEvent(_ event: ListeningEvent) {
        guard listeningHistory.record(event) else {
            lastError = listeningHistory.lastError
            return
        }
    }

    private func recordListeningEvents(_ events: [ListeningEvent]) {
        guard listeningHistory.record(events) else {
            lastError = listeningHistory.lastError
            return
        }
    }

    private func removeListeningHistory(for trackID: UUID) {
        guard listeningHistory.removeTrack(trackID) else {
            lastError = listeningHistory.lastError
            return
        }
    }

    private func rebuildAutoDJRecommendations() {
        guard var session = autoDJSession else { return }
        let manualTracks = queue.upcomingTracks.filter {
            manuallyQueuedTrackIDs.contains($0.id)
        }
        queue.clearUpcoming()
        session.recommendationsByTrackID.removeAll()
        autoDJSession = session
        for track in manualTracks {
            queue.enqueueLater(track)
        }
        syncQueue()
        replenishAutoDJQueue()
    }

    private func replenishAutoDJQueue(targetCount: Int = 3) {
        guard var session = autoDJSession,
              let currentTrack else { return }

        let activeIDs = session.playedTrackIDs.union(
            [currentTrack.id] + queue.upcomingTracks.map(\.id)
        )
        let currentRecommendationCount = queue.upcomingTracks.reduce(into: 0) {
            if session.recommendationsByTrackID[$1.id] != nil { $0 += 1 }
        }
        let needed = max(0, targetCount - currentRecommendationCount)
        guard needed > 0 else { return }

        let recentTrackIDs = Set(
            listeningHistory.history.recentEvents
                .filter { $0.kind == .playback }
                .suffix(20)
                .map(\.trackID)
        )
        let context = AutoDJContext(
            favoriteIDs: session.favoriteIDs,
            playlistGroups: session.playlistGroups,
            recentTrackIDs: recentTrackIDs,
            excludedTrackIDs: session.excludedTrackIDs.union(activeIDs),
            preferredTracks: session.preferredTracks
        )
        let recommendations = AutoDJ.recommend(
            after: currentTrack,
            candidates: session.library,
            context: context,
            history: listeningHistory.history,
            limit: needed
        )
        for recommendation in recommendations {
            queue.enqueueLater(recommendation.track)
            session.recommendationsByTrackID[recommendation.track.id] = recommendation
        }
        autoDJSession = session
        syncQueue()
    }

    private func syncQueue() {
        activeQueue = queue.activeOrder
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
                pausePlayback()
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
            pausePlayback()
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
                self.pausePlayback()
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackRate)
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard currentTrack != nil else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackRate)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
