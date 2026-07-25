import UIKit
import XCTest
@testable import SunoPlayer

final class ArtworkStorageTests: XCTestCase {
    func testSaveImageResizesAndWritesDecodableJPEG() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunoPlayerArtworkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let data = try XCTUnwrap(source.pngData())

        try ArtworkStorage.saveImage(
            data,
            fileName: "cover.jpg",
            directory: directory,
            maxDimension: 100
        )

        let savedData = try Data(contentsOf: directory.appendingPathComponent("cover.jpg"))
        let savedImage = try XCTUnwrap(UIImage(data: savedData))
        XCTAssertEqual(savedImage.size.width, 100, accuracy: 0.5)
        XCTAssertEqual(savedImage.size.height, 50, accuracy: 0.5)
    }

    func testSaveImageRejectsInvalidImageData() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunoPlayerArtworkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try ArtworkStorage.saveImage(
                Data("not an image".utf8),
                fileName: "cover.jpg",
                directory: directory
            )
        )
    }
}
