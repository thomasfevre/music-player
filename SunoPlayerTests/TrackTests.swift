import XCTest
@testable import SunoPlayer

final class TrackTests: XCTestCase {

    func testGradientHueIsDeterministicAcrossInstances() {
        let a = Track(title: "One", fileName: "song-abc.m4a")
        let b = Track(title: "Different title", fileName: "song-abc.m4a")
        XCTAssertEqual(a.gradientHue1, b.gradientHue1, accuracy: 1e-12)
        XCTAssertEqual(a.gradientHue2, b.gradientHue2, accuracy: 1e-12)
    }

    func testStableHashIsConstant() {
        XCTAssertEqual(Track.stableHash("hello.m4a"), Track.stableHash("hello.m4a"))
        XCTAssertNotEqual(Track.stableHash("a.m4a"), Track.stableHash("b.m4a"))
    }

    func testStableHueInRange() {
        for name in ["", "a", "track_001.mp3", "Ω≈ç√.m4a", String(repeating: "x", count: 500)] {
            let hue = Track.stableHue(for: name)
            XCTAssertGreaterThanOrEqual(hue, 0)
            XCTAssertLessThan(hue, 1)
        }
    }

    func testCodableRoundTripPreservesHues() throws {
        let original = Track(title: "Song", artist: "Artist", fileName: "x.m4a", duration: 42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.gradientHue1, original.gradientHue1, accuracy: 1e-12)
        XCTAssertEqual(decoded.gradientHue2, original.gradientHue2, accuracy: 1e-12)
        XCTAssertEqual(decoded.duration, 42)
    }

    func testDisplayArtistFallback() {
        XCTAssertEqual(Track(title: "T", fileName: "f.m4a").displayArtist, "Unknown Artist")
        XCTAssertEqual(Track(title: "T", artist: "Real", fileName: "f.m4a").displayArtist, "Real")
    }

    func testEqualityByIdOnly() {
        let a = Track(title: "Same", fileName: "same.m4a")
        var copy = a
        copy.title = "Changed"
        XCTAssertEqual(a, copy) // same id
        let other = Track(title: "Same", fileName: "same.m4a")
        XCTAssertNotEqual(a, other) // different id
    }

    func testFileURLUnderDocuments() {
        let t = Track(title: "T", fileName: "tune.m4a")
        XCTAssertEqual(t.fileURL, Track.documentsDirectory.appendingPathComponent("tune.m4a"))
    }

    func testArtworkURLNilWhenNoArtwork() {
        XCTAssertNil(Track(title: "T", fileName: "tune.m4a").artworkURL)
    }

    func testArtworkURLUnderArtworkDirectory() {
        let t = Track(title: "T", fileName: "tune.m4a", artworkFileName: "tune.img")
        XCTAssertEqual(t.artworkURL, Track.artworkDirectory.appendingPathComponent("tune.img"))
    }

    func testCodableRoundTripPreservesArtworkFileName() throws {
        let original = Track(title: "Song", fileName: "x.m4a", artworkFileName: "x.img")
        let decoded = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.artworkFileName, "x.img")
    }

    func testDecodesLegacyJSONWithoutArtworkKey() throws {
        // Library entries saved before the artwork feature must still decode (artworkFileName == nil).
        let legacy = """
        {"id":"\(UUID().uuidString)","title":"Old","fileName":"old.m4a","duration":12,
         "dateImported":0,"gradientHue1":0.1,"gradientHue2":0.2}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Track.self, from: legacy)
        XCTAssertNil(decoded.artworkFileName)
        XCTAssertEqual(decoded.title, "Old")
    }
}
