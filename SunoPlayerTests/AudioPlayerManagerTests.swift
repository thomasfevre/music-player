import XCTest
import Combine
import AVFoundation
@testable import SunoPlayer

@MainActor
final class AudioPlayerManagerTests: XCTestCase {

    private var createdFileNames: [String] = []
    private var createdHistoryURLs: [URL] = []

    override func setUp() {
        super.setUp()
        // The app configures this at launch; tests must too so setActive(true) succeeds.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP])
    }

    /// Polls `condition` on the main actor until true or the timeout elapses.
    private func waitUntil(timeout: TimeInterval = 4, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    override func tearDown() {
        for name in createdFileNames {
            try? FileManager.default.removeItem(at: Track.documentsDirectory.appendingPathComponent(name))
        }
        for url in createdHistoryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdFileNames = []
        createdHistoryURLs = []
        super.tearDown()
    }

    private func makePlayableTrack(_ name: String, title: String) throws -> Track {
        let fileName = "test-\(name).wav"
        createdFileNames.append(fileName)
        let url = Track.documentsDirectory.appendingPathComponent(fileName)
        try TestSupport.silentWAV().write(to: url)
        return Track(title: title, fileName: fileName, duration: 0.4)
    }

    private func makeManager() -> (AudioPlayerManager, ListeningHistoryStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("listening-\(UUID().uuidString).json")
        createdHistoryURLs.append(url)
        let history = ListeningHistoryStore(fileURL: url)
        return (AudioPlayerManager(listeningHistory: history), history)
    }

    func testPlaySetsCurrentTrackSynchronously() throws {
        let manager = AudioPlayerManager()
        let track = try makePlayableTrack("a", title: "A")
        manager.play(track, in: [track])
        XCTAssertEqual(manager.currentTrack, track)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(manager.activeQueue, [track])
    }

    func testDeletingCurrentTrackClearsPlayback() throws {
        let manager = AudioPlayerManager()
        let track = try makePlayableTrack("current", title: "Current")
        manager.play(track, in: [track])
        XCTAssertEqual(manager.currentTrack, track)

        manager.handleTrackDeleted(track)
        XCTAssertNil(manager.currentTrack)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.currentTime, 0)
        XCTAssertTrue(manager.activeQueue.isEmpty)
    }

    func testDeletingNonCurrentTrackKeepsPlayback() throws {
        let manager = AudioPlayerManager()
        let a = try makePlayableTrack("a", title: "A")
        let b = try makePlayableTrack("b", title: "B")
        manager.play(a, in: [a, b])
        XCTAssertEqual(manager.currentTrack, a)

        manager.handleTrackDeleted(b)
        XCTAssertEqual(manager.currentTrack, a)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(manager.activeQueue, [a])
    }

    func testPlayNextStartsPlaybackWhenQueueIsEmpty() throws {
        let manager = AudioPlayerManager()
        let track = try makePlayableTrack("play-next-empty", title: "Next")

        manager.enqueueNext(track)

        XCTAssertEqual(manager.currentTrack, track)
        XCTAssertEqual(manager.activeQueue, [track])
        XCTAssertTrue(manager.isPlaying)
    }

    func testMissingFileSetsErrorAndClearsState() {
        let manager = AudioPlayerManager()
        // Track whose file was never written to disk.
        let ghost = Track(title: "Ghost", fileName: "does-not-exist-\(UUID().uuidString).m4a", duration: 5)
        manager.play(ghost, in: [ghost])
        XCTAssertNil(manager.currentTrack)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertNotNil(manager.lastError)
    }

    /// Exercises the REAL async-failure wiring (KVO on AVPlayerItem.status /
    /// FailedToPlayToEndTime): a corrupt file should asynchronously transition the
    /// player into a clean failed state with a published error.
    func testCorruptFileTriggersAsyncFailure() async throws {
        let manager = AudioPlayerManager()
        let fileName = "corrupt-\(UUID().uuidString).m4a"
        createdFileNames.append(fileName)
        let url = Track.documentsDirectory.appendingPathComponent(fileName)
        try Data((0..<2048).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        let track = Track(title: "Corrupt", fileName: fileName, duration: 5)

        manager.play(track, in: [track])

        // Wait for the asynchronous failure to land.
        let deadline = Date().addingTimeInterval(8)
        while manager.lastError == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertNotNil(manager.lastError, "Corrupt item should report a failure")
        XCTAssertFalse(manager.isPlaying)
        XCTAssertNil(manager.currentTrack)
    }

    func testInterruptionNotificationPausesThenResumes() async throws {
        let manager = AudioPlayerManager()
        let track = try makePlayableTrack("intr", title: "Intr")
        manager.play(track, in: [track])
        try await waitUntil { manager.isPlaying }
        XCTAssertTrue(manager.isPlaying)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        try await waitUntil { !manager.isPlaying }
        XCTAssertFalse(manager.isPlaying, "Interruption began should pause")

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )
        try await waitUntil { manager.isPlaying }
        XCTAssertTrue(manager.isPlaying, "Interruption ended with shouldResume should resume")
    }

    func testInterruptionEndedWithoutShouldResumeStaysPaused() async throws {
        let manager = AudioPlayerManager()
        let track = try makePlayableTrack("intr2", title: "Intr2")
        manager.play(track, in: [track])
        try await waitUntil { manager.isPlaying }

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        try await waitUntil { !manager.isPlaying }

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]
        )
        // Give the observer a chance to (not) resume.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(manager.isPlaying, "No shouldResume option → must stay paused")
    }

    func testInterruptionResumeAfterTrackClearedStaysStopped() async throws {
        let manager = AudioPlayerManager()
        let track = try makePlayableTrack("clr", title: "Clr")
        manager.play(track, in: [track])
        try await waitUntil { manager.isPlaying }

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        try await waitUntil { !manager.isPlaying }

        // Current track deleted while interrupted → player cleared.
        manager.handleTrackDeleted(track)
        XCTAssertNil(manager.currentTrack)

        // Resume requested, but there is nothing to resume — must not claim "playing".
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertNil(manager.currentTrack)
    }

    func testRouteChangeUnplugPauses() async throws {
        let manager = AudioPlayerManager()
        let track = try makePlayableTrack("route", title: "Route")
        manager.play(track, in: [track])
        try await waitUntil { manager.isPlaying }

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
        )
        try await waitUntil { !manager.isPlaying }
        XCTAssertFalse(manager.isPlaying, "Headphone unplug should pause")
    }

    func testShuffleToggleStaysConsistentWithNavigation() throws {
        let manager = AudioPlayerManager()
        let a = try makePlayableTrack("a", title: "A")
        let b = try makePlayableTrack("b", title: "B")
        let c = try makePlayableTrack("c", title: "C")
        manager.play(b, in: [a, b, c])
        manager.toggleShuffle()   // on
        manager.toggleShuffle()   // off → index must resync to B
        XCTAssertEqual(manager.currentTrack, b)
        manager.next()
        XCTAssertEqual(manager.currentTrack, c) // base order navigation intact
    }

    func testManualNextAndNaturalCompletionAreRecordedDifferently() async throws {
        let (manager, history) = makeManager()
        let first = try makePlayableTrack("history-first", title: "First")
        let second = try makePlayableTrack("history-second", title: "Second")

        manager.play(first, in: [first, second], source: .library)
        try await Task.sleep(nanoseconds: 120_000_000)
        manager.next()

        XCTAssertEqual(
            history.history.recentEvents.last(where: { $0.kind == .playback })?.endReason,
            .manualSkip
        )

        let third = try makePlayableTrack("history-third", title: "Third")
        manager.play(second, in: [second, third], source: .library)
        try await waitUntil(timeout: 2) { manager.currentTrack == third }

        XCTAssertEqual(
            history.history.recentEvents.last(where: { $0.kind == .playback })?.endReason,
            .naturalCompletion
        )
    }

    func testStartingAutoDJPreservesManualNextAndReplacesBaseUpcomingQueue() throws {
        let (manager, _) = makeManager()
        let current = try makePlayableTrack("auto-current", title: "Current")
        let manual = try makePlayableTrack("auto-manual", title: "Manual")
        let suggestedA = try makePlayableTrack("auto-a", title: "Suggested A")
        let suggestedB = try makePlayableTrack("auto-b", title: "Suggested B")

        manager.play(current, in: [current, suggestedA, suggestedB], source: .library)
        manager.enqueueNext(manual)

        XCTAssertTrue(
            manager.startAutoDJ(
                library: [current, manual, suggestedA, suggestedB],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        XCTAssertTrue(manager.isAutoDJEnabled)
        XCTAssertEqual(manager.activeQueue.dropFirst().first, manual)
        XCTAssertEqual(Set(manager.activeQueue.map(\.id)), Set([current, manual, suggestedA, suggestedB].map(\.id)))
        XCTAssertEqual(manager.autoDJUpcomingRecommendations.count, 2)
    }

    func testNegativeAutoDJFeedbackIsStoredAndAdvances() throws {
        let (manager, history) = makeManager()
        let current = try makePlayableTrack("feedback-current", title: "Current")
        let next = try makePlayableTrack("feedback-next", title: "Next")

        manager.play(current, in: [current, next], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [current, next],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        manager.submitAutoDJFeedback(positive: false)

        XCTAssertEqual(manager.currentTrack, next)
        XCTAssertEqual(history.summary(for: current.id).negativeFeedbackCount, 1)
        XCTAssertEqual(
            history.history.recentEvents.last(where: { $0.kind == .negativeFeedback })?.trackID,
            current.id
        )
    }

    func testAutoDJStopsAfterEveryLibraryTrackHasPlayedWithoutRepeating() throws {
        let (manager, _) = makeManager()
        let first = try makePlayableTrack("cycle-first", title: "First")
        let second = try makePlayableTrack("cycle-second", title: "Second")

        manager.play(first, in: [first, second], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [first, second],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        manager.next()

        XCTAssertEqual(manager.currentTrack, second)
        XCTAssertTrue(manager.autoDJUpcomingRecommendations.isEmpty)

        manager.next()

        XCTAssertFalse(manager.isAutoDJEnabled)
        XCTAssertEqual(manager.currentTrack, second)
        XCTAssertFalse(manager.isPlaying)
    }

    func testStartingAutoDJAtEndOfBaseQueueStillConsidersEarlierUnplayedTracks() throws {
        let (manager, _) = makeManager()
        let first = try makePlayableTrack("prefix-first", title: "First")
        let second = try makePlayableTrack("prefix-second", title: "Second")
        let current = try makePlayableTrack("prefix-current", title: "Current")

        manager.play(current, in: [first, second, current], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [first, second, current],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        XCTAssertEqual(
            Set(manager.autoDJUpcomingRecommendations.map(\.track.id)),
            Set([first.id, second.id])
        )
    }

    func testClearingQueueStopsAutoDJInsteadOfSilentlyRefillingIt() throws {
        let (manager, _) = makeManager()
        let first = try makePlayableTrack("clear-auto-first", title: "First")
        let second = try makePlayableTrack("clear-auto-second", title: "Second")

        manager.play(first, in: [first, second], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [first, second],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        manager.clearUpcoming()

        XCTAssertFalse(manager.isAutoDJEnabled)
        XCTAssertEqual(manager.activeQueue, [first])
    }

    func testStoppingAutoDJRemovesSuggestionsButKeepsManualQueue() throws {
        let (manager, _) = makeManager()
        let current = try makePlayableTrack("stop-current", title: "Current")
        let manual = try makePlayableTrack("stop-manual", title: "Manual")
        let suggested = try makePlayableTrack("stop-suggested", title: "Suggested")

        manager.play(current, in: [current, suggested], source: .library)
        manager.enqueueNext(manual)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [current, manual, suggested],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        manager.stopAutoDJ()

        XCTAssertFalse(manager.isAutoDJEnabled)
        XCTAssertEqual(manager.activeQueue, [current, manual])
    }

    func testPlayLaterDuringAutoDJSitsAfterManualTracksAndBeforeSuggestions() throws {
        let (manager, _) = makeManager()
        let current = try makePlayableTrack("later-current", title: "Current")
        let manualNext = try makePlayableTrack("later-next", title: "Manual Next")
        let manualLater = try makePlayableTrack("later-manual", title: "Manual Later")
        let suggestedA = try makePlayableTrack("later-a", title: "Suggested A")
        let suggestedB = try makePlayableTrack("later-b", title: "Suggested B")

        manager.play(current, in: [current, suggestedA, suggestedB], source: .library)
        manager.enqueueNext(manualNext)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [current, manualNext, manualLater, suggestedA, suggestedB],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        manager.enqueueLater(manualLater)

        XCTAssertEqual(
            Array(manager.activeQueue.dropFirst().prefix(2)),
            [manualNext, manualLater]
        )
        XCTAssertEqual(
            Set(manager.autoDJUpcomingRecommendations.map(\.track.id)),
            Set([suggestedA.id, suggestedB.id])
        )
    }

    func testPlayLaterForPreviouslyPlayedTrackMovesInsteadOfDuplicatingIt() throws {
        let (manager, _) = makeManager()
        let first = try makePlayableTrack("repeat-first", title: "First")
        let second = try makePlayableTrack("repeat-second", title: "Second")
        let third = try makePlayableTrack("repeat-third", title: "Third")

        manager.play(first, in: [first, second, third], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [first, second, third],
                favoriteIDs: [second.id],
                playlistGroups: []
            )
        )
        manager.next()

        manager.enqueueLater(first)

        XCTAssertEqual(manager.currentTrack, second)
        XCTAssertEqual(manager.activeQueue.filter { $0.id == first.id }.count, 1)
        XCTAssertEqual(manager.activeQueue.dropFirst().first, first)
        manager.next()
        XCTAssertEqual(manager.currentTrack, first)
    }

    func testQueueingCurrentTrackDuringAutoDJIsANoOp() throws {
        let (manager, history) = makeManager()
        let current = try makePlayableTrack("noop-current", title: "Current")
        let suggested = try makePlayableTrack("noop-suggested", title: "Suggested")

        manager.play(current, in: [current, suggested], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [current, suggested],
                favoriteIDs: [],
                playlistGroups: []
            )
        )
        let queueBefore = manager.activeQueue

        manager.enqueueLater(current)
        manager.enqueueNext(current)

        XCTAssertEqual(manager.activeQueue, queueBefore)
        XCTAssertFalse(history.history.recentEvents.contains {
            $0.trackID == current.id && ($0.kind == .queuedLater || $0.kind == .queuedNext)
        })
    }

    func testRemovingSuggestionExcludesItForTheRestOfTheSession() throws {
        let (manager, _) = makeManager()
        let current = try makePlayableTrack("exclude-current", title: "Current")
        let suggested = try makePlayableTrack("exclude-suggested", title: "Suggested")

        manager.play(current, in: [current, suggested], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [current, suggested],
                favoriteIDs: [],
                playlistGroups: []
            )
        )

        manager.removeUpcoming(at: IndexSet(integer: 0))

        XCTAssertTrue(manager.autoDJUpcomingRecommendations.isEmpty)
        XCTAssertEqual(manager.activeQueue, [current])
    }

    func testManuallyQueueingSuggestionChangesItsPlaybackSourceToQueue() throws {
        let (manager, history) = makeManager()
        let current = try makePlayableTrack("source-current", title: "Current")
        let suggested = try makePlayableTrack("source-suggested", title: "Suggested")

        manager.play(current, in: [current, suggested], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [current, suggested],
                favoriteIDs: [],
                playlistGroups: []
            )
        )
        manager.enqueueNext(suggested)
        manager.next()
        manager.next()

        let suggestedPlayback = history.history.recentEvents.last {
            $0.kind == .playback && $0.trackID == suggested.id
        }
        XCTAssertEqual(suggestedPlayback?.source, .queue)
    }

    func testPositiveFeedbackRebuildsRecommendationsFromSessionPreference() throws {
        let (manager, _) = makeManager()
        let current = try makePlayableTrack("prefer-current", title: "Current")
        var preferredCurrent = current
        preferredCurrent.artist = "NEON"
        let favorite = try makePlayableTrack("prefer-favorite", title: "Favorite")
        var similar = try makePlayableTrack("prefer-similar", title: "Similar")
        similar.artist = "NEON"

        manager.play(preferredCurrent, in: [preferredCurrent, favorite, similar], source: .library)
        XCTAssertTrue(
            manager.startAutoDJ(
                library: [preferredCurrent, favorite, similar],
                favoriteIDs: [favorite.id],
                playlistGroups: []
            )
        )
        XCTAssertEqual(manager.autoDJUpcomingRecommendations.first?.track, favorite)

        manager.submitAutoDJFeedback(positive: true)

        XCTAssertEqual(manager.autoDJUpcomingRecommendations.first?.track, similar)
        XCTAssertTrue(
            manager.autoDJUpcomingRecommendations.first?.reasons.contains(.positiveFeedback) == true
        )
    }

    func testDeletingTrackAndResettingLearningCleanHistoryOnly() throws {
        let (manager, history) = makeManager()
        let current = try makePlayableTrack("cleanup-current", title: "Current")
        history.record(.feedback(trackID: current.id, previousTrackID: nil, positive: true, at: Date()))

        manager.handleTrackDeleted(current)
        XCTAssertEqual(history.summary(for: current.id), TrackListeningSummary())

        let retained = UUID()
        history.record(.feedback(trackID: retained, previousTrackID: nil, positive: true, at: Date()))
        manager.resetListeningHistory()

        XCTAssertEqual(history.summary(for: retained), TrackListeningSummary())
        XCTAssertTrue(history.history.recentEvents.isEmpty)
    }
}
