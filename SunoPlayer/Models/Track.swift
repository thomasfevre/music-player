import Foundation
import SwiftUI

// MARK: - Sort Order
enum SortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case title = "Title"

    var id: String { rawValue }
}

enum TrackArtworkStyle: String, Codable, Equatable {
    case photo
    case color
    case listeningPoster
}

/// Metadata that can be recovered safely from the common `Artist - Title.mp3` naming pattern.
/// This is a fallback only: embedded audio tags always take precedence when they are present.
enum TrackFileNameMetadata {
    static func parse(_ fileName: String) -> (title: String, artist: String?) {
        let baseName = (fileName as NSString).deletingPathExtension
        let cleaned = baseName
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let separator = cleaned.range(of: " - ") else {
            return (cleaned, nil)
        }

        let artist = String(cleaned[..<separator.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(cleaned[separator.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !artist.isEmpty, !title.isEmpty else {
            return (cleaned, nil)
        }
        return (title, artist)
    }
}

/// Normalises multi-value audio tags for browse collections. A single tag such as
/// "Alesso, Katy Perry" contributes one entry to Alesso and one to Katy Perry.
enum TrackBrowseMetadata {
    static func components(from value: String?) -> [String] {
        guard let value else { return [] }

        let separators = CharacterSet(charactersIn: ",;")
        var seen = Set<String>()
        return value
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter {
                seen.insert(
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                ).inserted
            }
    }
}

// MARK: - Repeat Mode
enum RepeatMode: String, CaseIterable {
    case off, all, one

    var icon: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    /// Cycles off → all → one → off.
    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

// MARK: - Track Model
struct Track: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String?
    var album: String?
    var genre: String?
    let fileName: String
    var duration: TimeInterval
    let dateImported: Date

    /// File name of the embedded cover art extracted at import (stored under `Artwork/`).
    /// Optional and decoded leniently so libraries saved before this feature still load.
    var artworkFileName: String?

    /// File name of artwork explicitly selected by the user. Keeping it separate from embedded
    /// artwork lets "Reset" restore the original cover without re-reading the audio file.
    var customArtworkFileName: String?

    /// True when the user explicitly chose a generated color style instead of embedded artwork.
    /// Optional for backward-compatible decoding of existing libraries.
    var usesGeneratedArtwork: Bool?

    /// Explicit artwork choice. Kept optional so libraries saved before artwork styles continue
    /// to decode, with `usesGeneratedArtwork` used as the legacy color-style fallback.
    var artworkStyle: TrackArtworkStyle?

    /// Version of the metadata extraction pass applied to this track.
    /// Optional so libraries saved before metadata browsing can be backfilled once.
    var metadataScanVersion: Int?

    /// Hue values (0–1) used to procedurally generate a gradient for this track.
    var gradientHue1: Double
    var gradientHue2: Double

    // MARK: Shared

    /// The app's documents directory, resolved once (stable for the app's lifetime).
    static let documentsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    /// Directory holding extracted cover-art images.
    static let artworkDirectory: URL = {
        documentsDirectory.appendingPathComponent("Artwork", isDirectory: true)
    }()

    // MARK: Computed

    /// Resolved URL from the app's documents directory at runtime.
    var fileURL: URL {
        Self.documentsDirectory.appendingPathComponent(fileName)
    }

    var resolvedArtworkStyle: TrackArtworkStyle? {
        artworkStyle ?? (usesGeneratedArtwork == true ? .color : nil)
    }

    var usesListeningPoster: Bool {
        resolvedArtworkStyle == .listeningPoster
    }

    /// The selected photo takes precedence over artwork embedded in the audio file.
    var preferredArtworkFileName: String? {
        switch resolvedArtworkStyle {
        case .color, .listeningPoster:
            return nil
        case .photo:
            return customArtworkFileName ?? artworkFileName
        case nil:
            return customArtworkFileName ?? artworkFileName
        }
    }

    /// Resolved URL of the artwork currently shown by the app, if any.
    var artworkURL: URL? {
        guard let preferredArtworkFileName else { return nil }
        return Self.artworkDirectory.appendingPathComponent(preferredArtworkFileName)
    }

    var embeddedArtworkURL: URL? {
        guard let artworkFileName else { return nil }
        return Self.artworkDirectory.appendingPathComponent(artworkFileName)
    }

    var customArtworkURL: URL? {
        guard let customArtworkFileName else { return nil }
        return Self.artworkDirectory.appendingPathComponent(customArtworkFileName)
    }

    var displayArtist: String {
        artist ?? "Unknown Artist"
    }

    var displayAlbum: String {
        album ?? "Unknown Album"
    }

    var displayGenre: String {
        genre ?? "Unknown Genre"
    }

    func wasImported(onOrAfter date: Date) -> Bool {
        dateImported >= date
    }

    var displayGradientHues: (Double, Double) {
        resolvedArtworkStyle == .color || resolvedArtworkStyle == .listeningPoster
            ? (gradientHue1, gradientHue2)
            : (ArtworkTheme.violet.hue1, ArtworkTheme.violet.hue2)
    }

    var gradientColors: [Color] {
        let hues = displayGradientHues
        return [
            Color(hue: hues.0, saturation: 0.7, brightness: 0.75),
            Color(hue: hues.1, saturation: 0.8, brightness: 0.55)
        ]
    }

    // MARK: Init
    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        fileName: String,
        duration: TimeInterval = 0,
        dateImported: Date = Date(),
        artworkFileName: String? = nil,
        customArtworkFileName: String? = nil,
        usesGeneratedArtwork: Bool? = nil,
        artworkStyle: TrackArtworkStyle? = nil,
        metadataScanVersion: Int? = 1,
        gradientHue1: Double? = nil,
        gradientHue2: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.fileName = fileName
        self.duration = duration
        self.dateImported = dateImported
        self.artworkFileName = artworkFileName
        self.customArtworkFileName = customArtworkFileName
        self.usesGeneratedArtwork = usesGeneratedArtwork
        self.artworkStyle = artworkStyle
        self.metadataScanVersion = metadataScanVersion

        // Derive gradient hues from a stable file-name hash for visual consistency.
        let hue = Self.stableHue(for: fileName)
        self.gradientHue1 = gradientHue1 ?? hue
        self.gradientHue2 = gradientHue2 ?? (hue + 0.25).truncatingRemainder(dividingBy: 1.0)
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Stable hashing

    /// Deterministic across process launches, unlike `String.hashValue`
    /// (which is seeded per-process since Swift 4.2). djb2 over UTF-8 bytes.
    static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return hash
    }

    /// A stable hue in 0..<1 derived from the file name.
    static func stableHue(for fileName: String) -> Double {
        let positive = ((stableHash(fileName) % 360) + 360) % 360
        return Double(positive) / 360.0
    }
}
