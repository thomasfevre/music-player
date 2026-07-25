import XCTest
@testable import SunoPlayer

final class AutoDJTests: XCTestCase {

    func testRecommendationsAreDeterministicAndRespectExclusions() {
        let current = TestSupport.track(title: "Current")
        let a = TestSupport.track(title: "A")
        let b = TestSupport.track(title: "B")
        let excluded = TestSupport.track(title: "Excluded")
        let context = AutoDJContext(
            favoriteIDs: [],
            playlistGroups: [],
            recentTrackIDs: [current.id],
            excludedTrackIDs: [excluded.id]
        )
        let history = ListeningHistory()

        let first = AutoDJ.recommend(
            after: current,
            candidates: [excluded, b, current, a],
            context: context,
            history: history,
            limit: 2,
            now: Date(timeIntervalSince1970: 10_000)
        )
        let second = AutoDJ.recommend(
            after: current,
            candidates: [a, current, b, excluded],
            context: context,
            history: history,
            limit: 2,
            now: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 2)
        XCTAssertFalse(first.map(\.track.id).contains(current.id))
        XCTAssertFalse(first.map(\.track.id).contains(excluded.id))
    }

    func testSuccessfulTransitionCompletionAndPlaylistMembershipWin() {
        let now = Date(timeIntervalSince1970: 20_000)
        let current = TestSupport.track(title: "Current", genre: "Electronic")
        let strong = TestSupport.track(title: "Strong", genre: "Electronic")
        let weak = TestSupport.track(title: "Weak", genre: "Rock")
        var history = ListeningHistory()

        history.record(
            .playback(
                trackID: strong.id,
                previousTrackID: current.id,
                source: .autoDJ,
                startedAt: now.addingTimeInterval(-200),
                endedAt: now.addingTimeInterval(-20),
                listenedSeconds: 180,
                duration: 180,
                endReason: .naturalCompletion,
                wasReplay: false
            )
        )
        history.record(
            .feedback(
                trackID: strong.id,
                previousTrackID: current.id,
                positive: true,
                at: now
            )
        )

        let result = AutoDJ.recommend(
            after: current,
            candidates: [weak, strong],
            context: AutoDJContext(
                favoriteIDs: [],
                playlistGroups: [[current.id, strong.id]],
                recentTrackIDs: [current.id],
                excludedTrackIDs: []
            ),
            history: history,
            limit: 2,
            now: now
        )

        XCTAssertEqual(result.first?.track, strong)
        XCTAssertTrue(result.first?.reasons.contains(.successfulTransition) == true)
        XCTAssertTrue(result.first?.reasons.contains(.samePlaylist) == true)
        XCTAssertTrue(result.first?.reasons.contains(.oftenCompleted) == true)
    }

    func testNegativeFeedbackAndEarlySkipsPushCandidateDown() {
        let now = Date(timeIntervalSince1970: 30_000)
        let current = TestSupport.track(title: "Current")
        let disliked = TestSupport.track(title: "Disliked")
        let neutral = TestSupport.track(title: "Neutral")
        var history = ListeningHistory()

        for offset in 0..<3 {
            history.record(
                .feedback(
                    trackID: disliked.id,
                    previousTrackID: current.id,
                    positive: false,
                    at: now.addingTimeInterval(TimeInterval(offset))
                )
            )
            history.record(
                .playback(
                    trackID: disliked.id,
                    previousTrackID: current.id,
                    source: .autoDJ,
                    startedAt: now,
                    endedAt: now.addingTimeInterval(5),
                    listenedSeconds: 5,
                    duration: 180,
                    endReason: .manualSkip,
                    wasReplay: false
                )
            )
        }

        let result = AutoDJ.recommend(
            after: current,
            candidates: [disliked, neutral],
            context: AutoDJContext(
                favoriteIDs: [],
                playlistGroups: [],
                recentTrackIDs: [current.id],
                excludedTrackIDs: []
            ),
            history: history,
            limit: 2,
            now: now
        )

        XCTAssertEqual(result.first?.track, neutral)
    }

    func testReasonsOnlyDescribeSignalsActuallyKnown() {
        let now = Date(timeIntervalSince1970: 40_000)
        let current = TestSupport.track(title: "Current", artist: "Artist", genre: nil)
        let candidate = TestSupport.track(title: "Candidate", artist: "Artist", genre: nil)

        let recommendation = AutoDJ.recommend(
            after: current,
            candidates: [candidate],
            context: AutoDJContext(
                favoriteIDs: [candidate.id],
                playlistGroups: [],
                recentTrackIDs: [current.id],
                excludedTrackIDs: []
            ),
            history: ListeningHistory(),
            limit: 1,
            now: now
        ).first

        XCTAssertEqual(
            recommendation?.reasons,
            [.favorite, .familiarArtist, .notPlayedRecently]
        )
        XCTAssertFalse(recommendation?.reasonText.localizedCaseInsensitiveContains("energy") == true)
        XCTAssertFalse(recommendation?.reasonText.localizedCaseInsensitiveContains("tempo") == true)
    }

    func testRecentlyPlayedTrackLosesToFreshCandidate() {
        let now = Date(timeIntervalSince1970: 50_000)
        let current = TestSupport.track(title: "Current")
        let recent = TestSupport.track(title: "Recent")
        let fresh = TestSupport.track(title: "Fresh")
        var history = ListeningHistory()
        history.record(
            .playback(
                trackID: recent.id,
                previousTrackID: nil,
                source: .library,
                startedAt: now.addingTimeInterval(-60),
                endedAt: now.addingTimeInterval(-30),
                listenedSeconds: 30,
                duration: 180,
                endReason: .replacedBySelection,
                wasReplay: false
            )
        )

        let result = AutoDJ.recommend(
            after: current,
            candidates: [recent, fresh],
            context: AutoDJContext(
                favoriteIDs: [],
                playlistGroups: [],
                recentTrackIDs: [current.id, recent.id],
                excludedTrackIDs: []
            ),
            history: history,
            limit: 2,
            now: now
        )

        XCTAssertEqual(result.first?.track, fresh)
        XCTAssertEqual(result.first?.reasons, [.notPlayedRecently])
    }

    func testPositiveSessionPreferenceBoostsSimilarCandidates() {
        let current = TestSupport.track(title: "Current")
        let preferred = TestSupport.track(title: "Preferred", artist: "NEON", genre: "Synthwave")
        let similar = TestSupport.track(title: "Similar", artist: "NEON", genre: "Synthwave")
        let favorite = TestSupport.track(title: "Favorite")

        let withoutPreference = AutoDJ.recommend(
            after: current,
            candidates: [similar, favorite],
            context: AutoDJContext(
                favoriteIDs: [favorite.id],
                playlistGroups: [],
                recentTrackIDs: [],
                excludedTrackIDs: []
            ),
            history: ListeningHistory(),
            limit: 2
        )
        let withPreference = AutoDJ.recommend(
            after: current,
            candidates: [similar, favorite],
            context: AutoDJContext(
                favoriteIDs: [favorite.id],
                playlistGroups: [],
                recentTrackIDs: [],
                excludedTrackIDs: [],
                preferredTracks: [preferred]
            ),
            history: ListeningHistory(),
            limit: 2
        )

        XCTAssertEqual(withoutPreference.first?.track, favorite)
        XCTAssertEqual(withPreference.first?.track, similar)
        XCTAssertTrue(withPreference.first?.reasons.contains(.positiveFeedback) == true)
    }

    func testEveryRecommendationHasATrustworthyReason() {
        let current = TestSupport.track(title: "Current")
        let recentCandidate = TestSupport.track(title: "Recent")

        let recommendation = AutoDJ.recommend(
            after: current,
            candidates: [recentCandidate],
            context: AutoDJContext(
                favoriteIDs: [],
                playlistGroups: [],
                recentTrackIDs: [recentCandidate.id],
                excludedTrackIDs: []
            ),
            history: ListeningHistory(),
            limit: 1
        ).first

        XCTAssertEqual(recommendation?.reasons, [.libraryPick])
        XCTAssertFalse(recommendation?.reasonText.isEmpty == true)
    }

    func testAvailableAlbumMetadataInfluencesRecommendation() {
        let current = TestSupport.track(title: "Current", album: "Night Signals")
        let sameAlbum = TestSupport.track(title: "Same Album", album: "Night Signals")
        let unrelated = TestSupport.track(title: "Unrelated", album: "Elsewhere")

        let recommendations = AutoDJ.recommend(
            after: current,
            candidates: [unrelated, sameAlbum],
            context: AutoDJContext(
                favoriteIDs: [],
                playlistGroups: [],
                recentTrackIDs: [],
                excludedTrackIDs: []
            ),
            history: ListeningHistory(),
            limit: 2
        )

        XCTAssertEqual(recommendations.first?.track, sameAlbum)
        XCTAssertTrue(recommendations.first?.reasons.contains(.sameAlbum) == true)
    }
}
