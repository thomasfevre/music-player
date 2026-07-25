import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let m3uPlaylist = UTType(filenameExtension: "m3u") ?? .plainText
}

struct M3UPlaylistDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.m3uPlaylist, .plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
