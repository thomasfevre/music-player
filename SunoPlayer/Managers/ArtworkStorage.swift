import UIKit

enum ArtworkStorage {
    /// Normalizes user-selected images before storing them to keep the library lightweight.
    static func saveImage(
        _ data: Data,
        fileName: String,
        directory: URL,
        maxDimension: CGFloat = 1_600
    ) throws {
        guard let source = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let longestSide = max(source.size.width, source.size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let size = CGSize(
            width: max(1, source.size.width * scale),
            height: max(1, source.size.height * scale)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            source.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let jpeg = rendered.jpegData(compressionQuality: 0.88) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try jpeg.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func removeIfPresent(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
