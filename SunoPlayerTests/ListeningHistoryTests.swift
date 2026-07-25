import XCTest
@testable import SunoPlayer

final class ListeningHistoryTests: XCTestCase {

    func testNaturalCompletionAndEarlySkipStayDistinct() {
        let first = UUID()
        let second = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        var history = ListeningHistory(maxRecentEvents: 20)

        history.record(
            ListeningEvent.playback(
                trackID: first,
                previousTrackID: nil,
                source: .library,
                startedAt: start,
                endedAt: start.addingTimeInterval(180),
                listenedSeconds: 180,
                duration: 180,
                endReason: .naturalCompletion,
                wasReplay: false
            )
        )
        history.record(
            ListeningEvent.playback(
                trackID: second,
                previousTrackID: first,
                source: .queue,
                startedAt: start.addingTimeInterval(180),
                endedAt: start.addingTimeInterval(187),
                listenedSeconds: 7,
                duration: 200,
                endReason: .manualSkip,
                wasReplay: false
            )
        )

        XCTAssertEqual(history.summary(for: first).completionCount, 1)
        XCTAssertEqual(history.summary(for: first).earlySkipCount, 0)
        XCTAssertEqual(history.summary(for: second).completionCount, 0)
        XCTAssertEqual(history.summary(for: second).earlySkipCount, 1)
        XCTAssertEqual(history.transition(from: first, to: second)?.earlySkipCount, 1)
    }

    func testLateSkipRemainsAggregatedBeyondRecentEvents() {
        let previous = UUID()
        let track = UUID()
        var history = ListeningHistory(maxRecentEvents: 1)

        history.record(
            .playback(
                trackID: track,
                previousTrackID: previous,
                source: .autoDJ,
                startedAt: Date(timeIntervalSince1970: 1_000),
                endedAt: Date(timeIntervalSince1970: 1_100),
                listenedSeconds: 100,
                duration: 180,
                endReason: .manualSkip,
                wasReplay: false
            )
        )
        history.record(.action(trackID: UUID(), kind: .queuedLater, at: Date()))

        XCTAssertEqual(history.recentEvents.count, 1)
        XCTAssertEqual(history.summary(for: track).lateSkipCount, 1)
        XCTAssertEqual(history.summary(for: track).earlySkipCount, 0)
        XCTAssertEqual(history.transition(from: previous, to: track)?.lateSkipCount, 1)
    }

    func testFeedbackAndReplayUpdateSummariesAndTransition() {
        let previous = UUID()
        let track = UUID()
        let now = Date(timeIntervalSince1970: 2_000)
        var history = ListeningHistory(maxRecentEvents: 20)

        history.record(
            ListeningEvent.playback(
                trackID: track,
                previousTrackID: previous,
                source: .autoDJ,
                startedAt: now,
                endedAt: now.addingTimeInterval(120),
                listenedSeconds: 120,
                duration: 180,
                endReason: .replacedBySelection,
                wasReplay: true
            )
        )
        history.record(.feedback(trackID: track, previousTrackID: previous, positive: true, at: now))

        XCTAssertEqual(history.summary(for: track).playCount, 1)
        XCTAssertEqual(history.summary(for: track).replayCount, 1)
        XCTAssertEqual(history.summary(for: track).positiveFeedbackCount, 1)
        XCTAssertEqual(history.transition(from: previous, to: track)?.positiveFeedbackCount, 1)
    }

    func testRecentHistoryIsBounded() {
        let track = UUID()
        var history = ListeningHistory(maxRecentEvents: 3)

        for offset in 0..<5 {
            history.record(
                .action(
                    trackID: track,
                    kind: .queuedLater,
                    at: Date(timeIntervalSince1970: TimeInterval(offset))
                )
            )
        }

        XCTAssertEqual(history.recentEvents.count, 3)
        XCTAssertEqual(history.recentEvents.compactMap(\.date), [
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 3),
            Date(timeIntervalSince1970: 4)
        ])
    }

    func testRemovingTrackCleansEventsSummariesAndTransitions() {
        let removed = UUID()
        let other = UUID()
        let now = Date(timeIntervalSince1970: 3_000)
        var history = ListeningHistory(maxRecentEvents: 20)

        history.record(.feedback(trackID: removed, previousTrackID: other, positive: true, at: now))
        history.record(.feedback(trackID: other, previousTrackID: removed, positive: false, at: now))

        history.removeTrack(removed)

        XCTAssertEqual(history.summary(for: removed), TrackListeningSummary())
        XCTAssertTrue(history.recentEvents.allSatisfy {
            $0.trackID != removed && $0.relatedTrackID != removed
        })
        XCTAssertNil(history.transition(from: other, to: removed))
        XCTAssertNil(history.transition(from: removed, to: other))
    }

    func testResetRemovesLearningWithoutAffectingExternalLibraryData() {
        let track = UUID()
        var history = ListeningHistory(maxRecentEvents: 20)
        history.record(.action(trackID: track, kind: .favoriteAdded, at: Date()))

        history.reset()

        XCTAssertTrue(history.recentEvents.isEmpty)
        XCTAssertEqual(history.summary(for: track), TrackListeningSummary())
        XCTAssertTrue(history.transitions.isEmpty)
    }

    func testCodableRoundTripPreservesLearning() throws {
        let track = UUID()
        var original = ListeningHistory(maxRecentEvents: 20)
        original.record(.feedback(trackID: track, previousTrackID: nil, positive: true, at: Date()))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ListeningHistory.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    @MainActor
    func testFailedSaveRollsBackMutationAndExposesError() throws {
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-block-\(UUID().uuidString)")
        try Data("block".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }
        let impossibleURL = blockingFile.appendingPathComponent("listening-history.json")
        let store = ListeningHistoryStore(fileURL: impossibleURL)
        let trackID = UUID()

        XCTAssertFalse(
            store.record(.feedback(
                trackID: trackID,
                previousTrackID: nil,
                positive: true,
                at: Date()
            ))
        )

        XCTAssertEqual(store.summary(for: trackID), TrackListeningSummary())
        XCTAssertNotNil(store.lastError)
    }
}
