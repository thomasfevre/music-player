import Foundation
import SwiftUI

// MARK: - Sort Order
enum SortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case title = "Title"

    var id: String { rawValue }
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
    let fileName: String
    var duration: TimeInterval
    let dateImported: Date

    /// File name of the embedded cover art extracted at import (stored under `Artwork/`).
    /// Optional and decoded leniently so libraries saved before this feature still load.
    var artworkFileName: String?

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

    /// Resolved URL of the extracted cover art, if any.
    var artworkURL: URL? {
        guard let artworkFileName else { return nil }
        return Self.artworkDirectory.appendingPathComponent(artworkFileName)
    }

    var displayArtist: String {
        artist ?? "Unknown Artist"
    }

    var gradientColors: [Color] {
        [
            Color(hue: gradientHue1, saturation: 0.7, brightness: 0.75),
            Color(hue: gradientHue2, saturation: 0.8, brightness: 0.55)
        ]
    }

    // MARK: Init
    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        fileName: String,
        duration: TimeInterval = 0,
        dateImported: Date = Date(),
        artworkFileName: String? = nil,
        gradientHue1: Double? = nil,
        gradientHue2: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.fileName = fileName
        self.duration = duration
        self.dateImported = dateImported
        self.artworkFileName = artworkFileName

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
