import XCTest
@testable import SunoPlayer

final class M3UPlaylistCodecTests: XCTestCase {
    func testEncodeAndDecodePreservesUnicodeFileNames() {
        let tracks = [
            TestSupport.track(title: "Été", fileName: "Été.mp3"),
            TestSupport.track(title: "夜", fileName: "夜.m4a")
        ]

        let encoded = M3UPlaylistCodec.encode(tracks)

        XCTAssertEqual(M3UPlaylistCodec.fileNames(in: encoded), ["Été.mp3", "夜.m4a"])
    }

    func testResolveMatchesPathsCaseInsensitivelyAndReportsMissing() {
        let first = TestSupport.track(title: "One", fileName: "One.mp3")
        let second = TestSupport.track(title: "Two", fileName: "two.M4A")
        let text = "#EXTM3U\nMusic/one.MP3\nmissing.mp3\n./two.m4a\n"

        let result = M3UPlaylistCodec.resolve(text, in: [second, first])

        XCTAssertEqual(result.tracks.map(\.id), [first.id, second.id])
        XCTAssertEqual(result.missingFileNames, ["missing.mp3"])
    }

    func testDecodeIgnoresCommentsBlankLinesAndDuplicatePaths() {
        let text = "#EXTM3U\n\n#EXTINF:123,Track\nsong.mp3\nfolder/song.mp3\n"

        XCTAssertEqual(M3UPlaylistCodec.fileNames(in: text), ["song.mp3"])
    }

    func testDecodeNormalizesWindowsPathsFileURLsAndBOM() {
        let text = "\u{feff}#EXTM3U\nC:\\\\Music\\\\Song One.mp3\nfile:///Music/My%20Song.mp3\n"

        XCTAssertEqual(
            M3UPlaylistCodec.fileNames(in: text),
            ["Song One.mp3", "My Song.mp3"]
        )
    }

    func testRoundTripPreservesLiteralPercentEscapesAndLeadingHash() {
        let tracks = [
            TestSupport.track(title: "Percent", fileName: "100%20Hits.mp3"),
            TestSupport.track(title: "Hash", fileName: "#song.mp3")
        ]

        XCTAssertEqual(
            M3UPlaylistCodec.fileNames(in: M3UPlaylistCodec.encode(tracks)),
            ["100%20Hits.mp3", "#song.mp3"]
        )
    }
}
