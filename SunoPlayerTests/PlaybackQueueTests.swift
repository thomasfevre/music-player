import XCTest
@testable import SunoPlayer

final class PlaybackQueueTests: XCTestCase {

    private func makeABC() -> (Track, Track, Track) {
        (TestSupport.track(title: "A"), TestSupport.track(title: "B"), TestSupport.track(title: "C"))
    }

    func testNextAdvancesThenStopsWithRepeatOff() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: a)
        XCTAssertEqual(q.next().flatMap { q.track(at: $0) }, b)
        XCTAssertEqual(q.next().flatMap { q.track(at: $0) }, c)
        XCTAssertNil(q.next()) // end of queue, repeat off
    }

    func testNextWrapsWithRepeatAll() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.repeatMode = .all
        q.setQueue([a, b, c], startAt: c)
        XCTAssertEqual(q.next().flatMap { q.track(at: $0) }, a)
    }

    func testNextRepeatOneReturnsSameIndex() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.repeatMode = .one
        q.setQueue([a, b, c], startAt: b)
        XCTAssertEqual(q.next().flatMap { q.track(at: $0) }, b)
    }

    func testPreviousRestartsWhenPastThreeSeconds() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: b)
        XCTAssertEqual(q.previous(currentTime: 5), .restart)
    }

    func testPreviousGoesBack() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: b)
        XCTAssertEqual(q.previous(currentTime: 0), .play(index: 0))
        XCTAssertEqual(q.currentTrack, a)
    }

    func testPreviousAtStartRestartsWithRepeatOff() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: a)
        XCTAssertEqual(q.previous(currentTime: 0), .restart)
    }

    func testPreviousAtStartWrapsWithRepeatAll() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.repeatMode = .all
        q.setQueue([a, b, c], startAt: a)
        XCTAssertEqual(q.previous(currentTime: 0), .play(index: 2))
        XCTAssertEqual(q.currentTrack, c)
    }

    func testShuffleEnableKeepsCurrentTrackFirst() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: b)
        q.setShuffle(true, shuffleSeed: { _ in [c, a, b] })
        XCTAssertEqual(q.currentTrack, b)
        XCTAssertEqual(q.activeOrder.first, b)
        XCTAssertEqual(q.currentIndex, 0)
    }

    /// Regression: disabling shuffle must resync the index to the current track's
    /// position in the base order, otherwise next/previous jump to an unrelated track.
    func testShuffleDisableResyncsIndexToBaseOrder() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: b)
        q.setShuffle(true, shuffleSeed: { _ in [c, a, b] }) // current B → index 0 in shuffled
        q.setShuffle(false)
        XCTAssertEqual(q.currentTrack, b)
        XCTAssertEqual(q.currentIndex, 1) // B is at index 1 in base order [A,B,C]
        // And navigation is now correct in base order:
        XCTAssertEqual(q.next().flatMap { q.track(at: $0) }, c)
    }

    func testRemoveCurrentReturnsTrue() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: b)
        XCTAssertTrue(q.remove(b))
        XCTAssertFalse(q.activeOrder.contains(b))
    }

    func testRemoveNonCurrentKeepsCurrent() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: b)
        XCTAssertFalse(q.remove(c))
        XCTAssertEqual(q.currentTrack, b)
        XCTAssertEqual(q.activeOrder, [a, b])
    }

    func testRemoveBeforeCurrentAdjustsIndex() {
        let (a, b, c) = makeABC()
        var q = PlaybackQueue()
        q.setQueue([a, b, c], startAt: c)
        XCTAssertFalse(q.remove(a))
        XCTAssertEqual(q.currentTrack, c)
        XCTAssertEqual(q.currentIndex, 1) // C now at index 1 in [B,C]
    }

    func testEmptyQueueNavigationIsSafe() {
        var q = PlaybackQueue()
        XCTAssertNil(q.next())
        XCTAssertEqual(q.previous(currentTime: 0), .none)
        XCTAssertNil(q.currentTrack)
    }
}
