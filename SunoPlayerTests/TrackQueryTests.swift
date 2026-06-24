import XCTest
@testable import SunoPlayer

final class TrackQueryTests: XCTestCase {

    private func sample() -> [Track] {
        let t0 = Date(timeIntervalSince1970: 0)
        return [
            TestSupport.track(title: "Bohemian Rhapsody", artist: "Queen", dateImported: t0.addingTimeInterval(100)),
            TestSupport.track(title: "alpha", artist: "Daft Punk", dateImported: t0.addingTimeInterval(300)),
            TestSupport.track(title: "Zebra", artist: nil, dateImported: t0.addingTimeInterval(200))
        ]
    }

    func testEmptySearchReturnsAll() {
        XCTAssertEqual(TrackQuery.apply(tracks: sample(), searchText: "", sortOrder: .newest).count, 3)
    }

    func testWhitespaceSearchReturnsAll() {
        XCTAssertEqual(TrackQuery.apply(tracks: sample(), searchText: "   ", sortOrder: .newest).count, 3)
    }

    func testSearchByTitleCaseInsensitive() {
        let r = TrackQuery.apply(tracks: sample(), searchText: "bohemian", sortOrder: .newest)
        XCTAssertEqual(r.map(\.title), ["Bohemian Rhapsody"])
    }

    func testSearchByArtist() {
        let r = TrackQuery.apply(tracks: sample(), searchText: "daft", sortOrder: .newest)
        XCTAssertEqual(r.map(\.title), ["alpha"])
    }

    func testSearchMatchesUnknownArtistFallback() {
        let r = TrackQuery.apply(tracks: sample(), searchText: "unknown", sortOrder: .newest)
        XCTAssertEqual(r.map(\.title), ["Zebra"]) // artist nil → "Unknown Artist"
    }

    func testSortNewestFirst() {
        let r = TrackQuery.apply(tracks: sample(), searchText: "", sortOrder: .newest)
        XCTAssertEqual(r.map(\.title), ["alpha", "Zebra", "Bohemian Rhapsody"])
    }

    func testSortOldestFirst() {
        let r = TrackQuery.apply(tracks: sample(), searchText: "", sortOrder: .oldest)
        XCTAssertEqual(r.map(\.title), ["Bohemian Rhapsody", "Zebra", "alpha"])
    }

    func testSortByTitleCaseInsensitive() {
        let r = TrackQuery.apply(tracks: sample(), searchText: "", sortOrder: .title)
        XCTAssertEqual(r.map(\.title), ["alpha", "Bohemian Rhapsody", "Zebra"])
    }
}
