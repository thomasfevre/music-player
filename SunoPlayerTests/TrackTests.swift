import XCTest
@testable import SunoPlayer

final class TrackTests: XCTestCase {

    func testGradientHueIsDeterministicAcrossInstances() {
        let a = Track(title: "One", fileName: "song-abc.m4a")
        let b = Track(title: "Different title", fileName: "song-abc.m4a")
        XCTAssertEqual(a.gradientHue1, b.gradientHue1, accuracy: 1e-12)
        XCTAssertEqual(a.gradientHue2, b.gradientHue2, accuracy: 1e-12)
    }

    func testDefaultArtworkUsesConsistentBrandGradient() {
        let first = Track(title: "One", fileName: "one.m4a")
        let second = Track(title: "Two", fileName: "completely-different.mp3")

        XCTAssertEqual(first.displayGradientHues.0, ArtworkTheme.violet.hue1)
        XCTAssertEqual(first.displayGradientHues.1, ArtworkTheme.violet.hue2)
        XCTAssertEqual(first.displayGradientHues.0, second.displayGradientHues.0)
        XCTAssertEqual(first.displayGradientHues.1, second.displayGradientHues.1)
    }

    func testSelectedGeneratedThemeUsesStoredHues() {
        var track = Track(
            title: "One",
            fileName: "one.m4a",
            gradientHue1: 0.1,
            gradientHue2: 0.2
        )
        track.usesGeneratedArtwork = true

        XCTAssertEqual(track.displayGradientHues.0, 0.1)
        XCTAssertEqual(track.displayGradientHues.1, 0.2)
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

    func testFileNameMetadataRecoversArtistAndTitleWithoutSplittingRemixSuffix() {
        let metadata = TrackFileNameMetadata.parse("Showtek - Bouncer - Extended Mix.mp3")

        XCTAssertEqual(metadata.artist, "Showtek")
        XCTAssertEqual(metadata.title, "Bouncer - Extended Mix")
    }

    func testFileNameMetadataLeavesUnstructuredNamesAsTitleOnly() {
        let metadata = TrackFileNameMetadata.parse("Instrumental_demo.mp3")

        XCTAssertNil(metadata.artist)
        XCTAssertEqual(metadata.title, "Instrumental demo")
    }

    func testImportDateCutoffIncludesTheCutoffInstant() {
        let cutoff = Date(timeIntervalSince1970: 1_000)
        let atCutoff = Track(title: "A", fileName: "a.mp3", dateImported: cutoff)
        let beforeCutoff = Track(title: "B", fileName: "b.mp3", dateImported: cutoff.addingTimeInterval(-1))

        XCTAssertTrue(atCutoff.wasImported(onOrAfter: cutoff))
        XCTAssertFalse(beforeCutoff.wasImported(onOrAfter: cutoff))
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

    func testCustomArtworkTakesPrecedenceWithoutDiscardingEmbeddedArtwork() {
        let track = Track(
            title: "T",
            fileName: "tune.m4a",
            artworkFileName: "embedded.img",
            customArtworkFileName: "custom.jpg"
        )

        XCTAssertEqual(track.preferredArtworkFileName, "custom.jpg")
        XCTAssertEqual(track.artworkURL, Track.artworkDirectory.appendingPathComponent("custom.jpg"))
        XCTAssertEqual(
            track.embeddedArtworkURL,
            Track.artworkDirectory.appendingPathComponent("embedded.img")
        )
    }

    func testGeneratedArtworkCanTemporarilyHideEmbeddedArtwork() {
        var track = Track(
            title: "T",
            fileName: "tune.m4a",
            artworkFileName: "embedded.img"
        )

        track.usesGeneratedArtwork = true
        XCTAssertNil(track.preferredArtworkFileName)
        XCTAssertNil(track.artworkURL)
        XCTAssertNotNil(track.embeddedArtworkURL)
    }

    func testListeningPosterHidesPhotoAndEmbeddedArtwork() {
        let track = Track(
            title: "T",
            fileName: "tune.m4a",
            artworkFileName: "embedded.img",
            customArtworkFileName: "custom.jpg",
            artworkStyle: .listeningPoster
        )

        XCTAssertTrue(track.usesListeningPoster)
        XCTAssertNil(track.preferredArtworkFileName)
        XCTAssertNil(track.artworkURL)
    }

    func testListeningPosterUsesStoredGradientHues() {
        let track = Track(
            title: "T",
            fileName: "tune.m4a",
            artworkStyle: .listeningPoster,
            gradientHue1: 0.1,
            gradientHue2: 0.2
        )

        XCTAssertEqual(track.displayGradientHues.0, 0.1)
        XCTAssertEqual(track.displayGradientHues.1, 0.2)
    }

    func testCodableRoundTripPreservesArtworkStyle() throws {
        let original = Track(title: "Song", fileName: "x.m4a", artworkStyle: .listeningPoster)
        let decoded = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.artworkStyle, .listeningPoster)
        XCTAssertTrue(decoded.usesListeningPoster)
    }

    func testCodableRoundTripPreservesArtworkFileName() throws {
        let original = Track(
            title: "Song",
            artist: "Artist",
            album: "Album",
            genre: "Synthwave",
            fileName: "x.m4a",
            artworkFileName: "x.img"
        )
        let decoded = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.artworkFileName, "x.img")
        XCTAssertEqual(decoded.album, "Album")
        XCTAssertEqual(decoded.genre, "Synthwave")
        XCTAssertEqual(decoded.metadataScanVersion, 1)
    }

    func testDecodesLegacyJSONWithoutArtworkKey() throws {
        // Library entries saved before the artwork feature must still decode (artworkFileName == nil).
        let legacy = """
        {"id":"\(UUID().uuidString)","title":"Old","fileName":"old.m4a","duration":12,
         "dateImported":0,"gradientHue1":0.1,"gradientHue2":0.2}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Track.self, from: legacy)
        XCTAssertNil(decoded.artworkFileName)
        XCTAssertNil(decoded.customArtworkFileName)
        XCTAssertNil(decoded.usesGeneratedArtwork)
        XCTAssertNil(decoded.album)
        XCTAssertNil(decoded.genre)
        XCTAssertNil(decoded.metadataScanVersion)
        XCTAssertEqual(decoded.title, "Old")
    }
}
