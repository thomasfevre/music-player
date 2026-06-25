import XCTest
@testable import SunoPlayer

final class PlaybackSessionTests: XCTestCase {

    // MARK: - PlaybackRestore

    func testResolveNilSnapshotReturnsNil() {
        XCTAssertNil(PlaybackRestore.resolve(nil, in: [TestSupport.track(title: "A")]))
    }

    func testResolveMissingTrackReturnsNil() {
        let saved = PersistedPlayback(trackID: UUID(), position: 10)
        XCTAssertNil(PlaybackRestore.resolve(saved, in: [TestSupport.track(title: "A")]))
    }

    func testResolveReturnsMatchingTrackAndPosition() {
        let track = TestSupport.track(title: "A", duration: 200)
        let saved = PersistedPlayback(trackID: track.id, position: 42)
        let result = PlaybackRestore.resolve(saved, in: [track])
        XCTAssertEqual(result?.track.id, track.id)
        XCTAssertEqual(result?.position, 42)
    }

    func testResolveClampsPositionToDuration() {
        let track = TestSupport.track(title: "A", duration: 100)
        let saved = PersistedPlayback(trackID: track.id, position: 500)
        XCTAssertEqual(PlaybackRestore.resolve(saved, in: [track])?.position, 100)
    }

    func testResolveClampsNegativePositionToZero() {
        let track = TestSupport.track(title: "A", duration: 100)
        let saved = PersistedPlayback(trackID: track.id, position: -10)
        XCTAssertEqual(PlaybackRestore.resolve(saved, in: [track])?.position, 0)
    }

    func testResolveKeepsPositionWhenDurationUnknown() {
        let track = TestSupport.track(title: "A", duration: 0)
        let saved = PersistedPlayback(trackID: track.id, position: 30)
        XCTAssertEqual(PlaybackRestore.resolve(saved, in: [track])?.position, 30)
    }

    func testPersistedPlaybackCodableRoundTrip() throws {
        let original = PersistedPlayback(trackID: UUID(), position: 12.5)
        let decoded = try JSONDecoder().decode(PersistedPlayback.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    // MARK: - SleepTimer

    func testSleepTimerAdvanceDecrements() {
        let tick = SleepTimer.advance(remaining: 60)
        XCTAssertEqual(tick.next, 59)
        XCTAssertFalse(tick.fired)
    }

    func testSleepTimerFiresAtZero() {
        let tick = SleepTimer.advance(remaining: 1)
        XCTAssertEqual(tick.next, 0)
        XCTAssertTrue(tick.fired)
    }

    func testSleepTimerFiresWhenOvershooting() {
        let tick = SleepTimer.advance(remaining: 0.5)
        XCTAssertTrue(tick.fired)
        XCTAssertEqual(tick.next, 0)
    }

    func testSleepTimerPresetsAreSortedAndPositive() {
        XCTAssertEqual(SleepTimer.presetMinutes, SleepTimer.presetMinutes.sorted())
        XCTAssertTrue(SleepTimer.presetMinutes.allSatisfy { $0 > 0 })
    }

    // MARK: - PlaybackSpeed

    func testPlaybackSpeedLabels() {
        XCTAssertEqual(PlaybackSpeed.label(1.0), "1x")
        XCTAssertEqual(PlaybackSpeed.label(2.0), "2x")
        XCTAssertEqual(PlaybackSpeed.label(1.5), "1.5x")
        XCTAssertEqual(PlaybackSpeed.label(0.75), "0.75x")
    }

    func testPlaybackSpeedDefaultIsOne() {
        XCTAssertEqual(PlaybackSpeed.default, 1.0)
        XCTAssertTrue(PlaybackSpeed.options.contains(PlaybackSpeed.default))
    }

    func testPlaybackSpeedOptionsSortedAndPositive() {
        XCTAssertEqual(PlaybackSpeed.options, PlaybackSpeed.options.sorted())
        XCTAssertTrue(PlaybackSpeed.options.allSatisfy { $0 > 0 })
    }
}
