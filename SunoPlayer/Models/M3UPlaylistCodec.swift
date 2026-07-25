import Foundation

enum M3UPlaylistCodec {
    struct Resolution {
        let tracks: [Track]
        let missingFileNames: [String]
    }

    static func encode(_ tracks: [Track]) -> String {
        let paths = tracks.map(\.fileName)
        return (["#EXTM3U"] + paths).joined(separator: "\n") + "\n"
    }

    static func fileNames(in text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fileName = URL(fileURLWithPath: line).lastPathComponent
            let key = fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted { result.append(fileName) }
        }
        return result
    }

    static func resolve(_ text: String, in library: [Track]) -> Resolution {
        let byName = Dictionary(
            library.map {
                ($0.fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var tracks: [Track] = []
        var missing: [String] = []

        for fileName in fileNames(in: text) {
            let key = fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let track = byName[key] {
                tracks.append(track)
            } else {
                missing.append(fileName)
            }
        }
        return Resolution(tracks: tracks, missingFileNames: missing)
    }
}
