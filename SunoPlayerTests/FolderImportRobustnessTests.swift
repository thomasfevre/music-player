import XCTest
@testable import SunoPlayer

final class FolderImportRobustnessTests: XCTestCase {
    func testLocalFilesNeverTriggerDownload() {
        XCTAssertFalse(ICloudFileMaterializer.shouldDownload(isUbiquitous: false, status: nil))
    }

    func testCloudPlaceholderTriggersDownload() {
        XCTAssertTrue(ICloudFileMaterializer.shouldDownload(isUbiquitous: true, status: .notDownloaded))
        XCTAssertTrue(ICloudFileMaterializer.shouldDownload(isUbiquitous: true, status: nil))
    }

    func testDownloadedCloudFileIsReady() {
        XCTAssertFalse(ICloudFileMaterializer.shouldDownload(isUbiquitous: true, status: .current))
    }

    func testJobStoreRoundTrip() throws {
        let job = FolderImportJob(
            id: UUID(),
            bookmark: Data([1, 2, 3]),
            folderName: "Mix",
            playlists: [
                .init(name: "Mix", relativePaths: ["a.mp3", "b.m4a"], collidesWithExisting: true)
            ],
            totalFiles: 2,
            strategy: "merge",
            createdAt: Date()
        )
        try FolderImportJobStore.save(job)
        defer { FolderImportJobStore.clear() }
        XCTAssertEqual(FolderImportJobStore.load(), job)
    }

    func testSummaryTracksEmptyPlaylists() {
        var summary = FolderImportSummary()
        summary.emptyPlaylists = ["Cloud Only"]
        summary.failures = 3
        XCTAssertEqual(summary.emptyPlaylists, ["Cloud Only"])
        XCTAssertEqual(summary.failures, 3)
    }
}
