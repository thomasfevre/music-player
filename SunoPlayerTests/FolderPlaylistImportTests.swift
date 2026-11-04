import XCTest
@testable import SunoPlayer

final class FolderPlaylistImportTests: XCTestCase {
    private func file(_ path: String, size: Int64 = 100) -> FolderImportPlanner.ScannedFile {
        FolderImportPlanner.ScannedFile(
            url: URL(fileURLWithPath: "/tmp/Folder/\(path)"),
            relativePath: path,
            byteCount: size
        )
    }

    func testEachFolderWithAudioBecomesOnePlaylist() {
        let plan = FolderImportPlanner.plan(
            scannedFiles: [
                file("Rock/a.mp3"), file("Rock/b.m4a"),
                file("Jazz/c.wav")
            ],
            existingLibraryFileNames: []
        )
        XCTAssertEqual(plan.playlists.map(\.name), ["Jazz", "Rock"])
        XCTAssertEqual(plan.totalTracks, 3)
    }

    func testNestedFoldersAreSeparatePlaylists() {
        let plan = FolderImportPlanner.plan(
            scannedFiles: [file("Mix/one.mp3"), file("Mix/Bonus/two.mp3")],
            existingLibraryFileNames: []
        )
        XCTAssertEqual(Set(plan.playlists.map(\.name)), ["Mix", "Bonus"])
    }

    func testTopLevelFilesUseRootFolderName() {
        let plan = FolderImportPlanner.plan(
            scannedFiles: [file("top.mp3")],
            existingLibraryFileNames: [],
            rootFolderName: "Summer 2026"
        )
        XCTAssertEqual(plan.playlists.first?.name, "Summer 2026")
    }

    func testAlreadyImportedFilesAreDuplicates() {
        let plan = FolderImportPlanner.plan(
            scannedFiles: [file("Rock/a.mp3"), file("Rock/new.mp3")],
            existingLibraryFileNames: ["a.MP3"]
        )
        XCTAssertEqual(plan.totalTracks, 1)
        XCTAssertEqual(plan.duplicateFileNames, ["Rock/a.mp3"])
    }

    func testNonAudioFilesAreIgnored() {
        let plan = FolderImportPlanner.plan(
            scannedFiles: [file("Rock/a.mp3"), file("Rock/cover.jpg"), file("Rock/notes.txt")],
            existingLibraryFileNames: []
        )
        XCTAssertEqual(plan.ignoredFileCount, 2)
        XCTAssertEqual(plan.totalTracks, 1)
    }

    func testExistingPlaylistNameIsFlaggedAsCollision() {
        let plan = FolderImportPlanner.plan(
            scannedFiles: [file("Rock/a.mp3"), file("Rock2/b.mp3")],
            existingLibraryFileNames: [],
            existingPlaylistNames: ["Rock"]
        )
        let rock = plan.playlists.first { $0.name == "Rock" }
        XCTAssertEqual(rock?.collidesWithExistingPlaylist, true)
        XCTAssertEqual(plan.collidingPlaylistNames, ["Rock"])
    }

    func testNewFolderNamesCollidingWithEachOtherStillGetSuffix() {
        let plan = FolderImportPlanner.plan(
            scannedFiles: [file("A/Rock/a.mp3"), file("B/Rock/b.mp3")],
            existingLibraryFileNames: []
        )
        XCTAssertEqual(plan.playlists.map(\.name), ["Rock", "Rock (2)"])
    }

    func testEmptyFolderProducesEmptyPlan() {
        let plan = FolderImportPlanner.plan(scannedFiles: [], existingLibraryFileNames: [])
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.totalTracks, 0)
    }
}
