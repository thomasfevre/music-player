import XCTest
import Combine
import AVFoundation
@testable import SunoPlayer

@MainActor
final class AudioPlayerManagerTests: XCTestCase {

    private var createdFileNames: [String] = []

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
        createdFileNames = []
        super.tearDown()
    }

    private func makePlayableTrack(_ name: String, title: String) throws -> Track {
        let fileName = "test-\(name).wav"
        createdFileNames.append(fileName)
        let url = Track.documentsDirectory.appendingPathComponent(fileName)
        try TestSupport.silentWAV().write(to: url)
        return Track(title: title, fileName: fileName, duration: 0.4)
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
}
