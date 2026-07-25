import XCTest
@testable import SunoPlayer

final class PlaylistTests: XCTestCase {

    // MARK: - Mutations

    func testAddTrackAppendsAndDedupes() {
        var p = Playlist(name: "P")
        let a = UUID(), b = UUID()
        XCTAssertTrue(p.addTrack(a))
        XCTAssertTrue(p.addTrack(b))
        XCTAssertFalse(p.addTrack(a)) // duplicate ignored
        XCTAssertEqual(p.trackIDs, [a, b])
    }

    func testAddTracksAppendsInOrderAndDedupesBatch() {
        var p = Playlist(name: "P")
        let existing = UUID(), first = UUID(), second = UUID()
        p.addTrack(existing)

        let addedCount = p.addTracks([first, existing, second, first])

        XCTAssertEqual(addedCount, 2)
        XCTAssertEqual(p.trackIDs, [existing, first, second])
    }

    func testContainsAndCount() {
        var p = Playlist(name: "P")
        let a = UUID()
        XCTAssertFalse(p.contains(a))
        p.addTrack(a)
        XCTAssertTrue(p.contains(a))
        XCTAssertEqual(p.count, 1)
    }

    func testRemoveTrack() {
        var p = Playlist(name: "P")
        let a = UUID(), b = UUID()
        p.addTrack(a); p.addTrack(b)
        p.removeTrack(a)
        XCTAssertEqual(p.trackIDs, [b])
    }

    func testMoveReordersLikeSwiftUI() {
        var p = Playlist(name: "P")
        let ids = (0..<4).map { _ in UUID() }
        ids.forEach { p.addTrack($0) }
        // Move first element to the end (SwiftUI semantics: destination is post-removal index).
        p.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(p.trackIDs, [ids[1], ids[2], ids[3], ids[0]])
    }

    func testMoveDownToFront() {
        var p = Playlist(name: "P")
        let ids = (0..<3).map { _ in UUID() }
        ids.forEach { p.addTrack($0) }
        p.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(p.trackIDs, [ids[2], ids[0], ids[1]])
    }

    func testMoveMultipleNonContiguous() {
        var p = Playlist(name: "P")
        let ids = (0..<5).map { _ in UUID() } // [A,B,C,D,E]
        ids.forEach { p.addTrack($0) }
        // Move A(0) and C(2) to offset 4 — SwiftUI/stdlib semantics → [B,D,A,C,E].
        p.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(p.trackIDs, [ids[1], ids[3], ids[0], ids[2], ids[4]])
    }

    func testMoveMultipleToFront() {
        var p = Playlist(name: "P")
        let ids = (0..<5).map { _ in UUID() }
        ids.forEach { p.addTrack($0) }
        // Move B(1) and D(3) to front → [B,D,A,C,E].
        p.move(fromOffsets: IndexSet([1, 3]), toOffset: 0)
        XCTAssertEqual(p.trackIDs, [ids[1], ids[3], ids[0], ids[2], ids[4]])
    }

    func testMovedHelperKeepsGhostsImplicitlyViaResolvedReorder() {
        // Simulates the manager path: reorder resolved ids only.
        let a = UUID(), b = UUID(), c = UUID()
        let reordered = Playlist.moved([a, b, c], fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(reordered, [b, c, a])
    }

    func testCodableRoundTrip() throws {
        var p = Playlist(name: "Road Trip")
        p.addTrack(UUID()); p.addTrack(UUID())
        let decoded = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    // MARK: - Resolver

    func testResolverPreservesPlaylistOrder() {
        let t1 = TestSupport.track(title: "One")
        let t2 = TestSupport.track(title: "Two")
        let t3 = TestSupport.track(title: "Three")
        var p = Playlist(name: "P")
        // Playlist order differs from library order.
        p.addTrack(t3.id); p.addTrack(t1.id)
        let resolved = PlaylistResolver.tracks(for: p, in: [t1, t2, t3])
        XCTAssertEqual(resolved.map(\.title), ["Three", "One"])
    }

    func testResolverSkipsMissingTracks() {
        let t1 = TestSupport.track(title: "One")
        var p = Playlist(name: "P")
        p.addTrack(t1.id); p.addTrack(UUID()) // second id not in library
        let resolved = PlaylistResolver.tracks(for: p, in: [t1])
        XCTAssertEqual(resolved.map(\.title), ["One"])
    }

    func testResolverEmptyWhenNoMatches() {
        var p = Playlist(name: "P")
        p.addTrack(UUID())
        XCTAssertTrue(PlaylistResolver.tracks(for: p, in: [TestSupport.track(title: "X")]).isEmpty)
    }

    func testSmartRulesMatchMetadataFavoritesAndRecentImports() {
        let now = Date(timeIntervalSince1970: 10_000)
        let track = TestSupport.track(
            title: "Night Drive",
            artist: "Nova",
            album: "City Lights",
            genre: "Synthwave",
            dateImported: now.addingTimeInterval(-3_600)
        )

        XCTAssertTrue(SmartPlaylistRule.artist("nova").matches(track, favoriteIDs: [], now: now))
        XCTAssertTrue(SmartPlaylistRule.album("lights").matches(track, favoriteIDs: [], now: now))
        XCTAssertTrue(SmartPlaylistRule.genre("synth").matches(track, favoriteIDs: [], now: now))
        XCTAssertTrue(SmartPlaylistRule.favorites.matches(track, favoriteIDs: [track.id], now: now))
        XCTAssertTrue(SmartPlaylistRule.recentlyAdded(days: 1).matches(track, favoriteIDs: [], now: now))
        XCTAssertFalse(SmartPlaylistRule.recentlyAdded(days: 0).matches(track, favoriteIDs: [], now: now))
    }

    func testSmartPlaylistResolverUpdatesFromLibrary() {
        let synth = TestSupport.track(title: "One", genre: "Synthwave")
        let jazz = TestSupport.track(title: "Two", genre: "Jazz")
        let playlist = Playlist(name: "Synth", smartRule: .genre("Synthwave"))

        XCTAssertEqual(
            PlaylistResolver.tracks(for: playlist, in: [jazz, synth]).map(\.id),
            [synth.id]
        )
    }

    func testLegacyPlaylistDecodesWithoutSmartRule() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Legacy","trackIDs":[],"dateCreated":0}
        """

        let decoded = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))

        XCTAssertNil(decoded.smartRule)
    }
}
