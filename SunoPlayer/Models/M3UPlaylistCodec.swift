import Foundation

enum M3UPlaylistCodec {
    struct Resolution {
        let tracks: [Track]
        let missingFileNames: [String]
    }

    static func encode(_ tracks: [Track]) -> String {
        // Prefix relative paths so a legitimate file name beginning with "#" is not
        // interpreted as an M3U directive when the exported file is read again.
        let paths = tracks.map { "./\($0.fileName)" }
        return (["#EXTM3U"] + paths).joined(separator: "\n") + "\n"
    }

    static func fileNames(in text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fileName = fileName(from: line)
            guard !fileName.isEmpty else { continue }
            let key = fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted { result.append(fileName) }
        }
        return result
    }

    private static func fileName(from line: String) -> String {
        if let url = URL(string: line), url.isFileURL {
            return url.lastPathComponent
        }
        let normalized = line.replacingOccurrences(of: "\\", with: "/")
        let component = normalized.split(separator: "/", omittingEmptySubsequences: true).last
            .map(String.init) ?? normalized
        // Percent-decode only true file URIs above. In an ordinary path, "%20" may be
        // part of the real file name.
        return component
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
