import Foundation

enum DefaultTrackArtworkStyle: String, CaseIterable, Identifiable {
    case original, color, listeningPoster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .color: return "Color"
        case .listeningPoster: return "Stats Poster"
        }
    }
}

enum ArtworkPreferences {
    private static let styleKey = "defaultTrackArtworkStyle"
    private static let uniqueColorsKey = "usesUniqueArtworkColors"

    static var defaultStyle: DefaultTrackArtworkStyle {
        get { DefaultTrackArtworkStyle(rawValue: UserDefaults.standard.string(forKey: styleKey) ?? "") ?? .original }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }

    static var usesUniqueColors: Bool {
        get { UserDefaults.standard.object(forKey: uniqueColorsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: uniqueColorsKey) }
    }

    static func apply(to track: inout Track) {
        switch defaultStyle {
        case .original:
            track.artworkStyle = nil
            track.usesGeneratedArtwork = nil
        case .color:
            track.artworkStyle = .color
            track.usesGeneratedArtwork = false
        case .listeningPoster:
            track.artworkStyle = .listeningPoster
            track.usesGeneratedArtwork = false
        }
        if usesUniqueColors {
            let hue = Track.stableHue(for: track.fileName)
            track.gradientHue1 = hue
            track.gradientHue2 = (hue + 0.25).truncatingRemainder(dividingBy: 1.0)
        } else {
            track.gradientHue1 = ArtworkTheme.violet.hue1
            track.gradientHue2 = ArtworkTheme.violet.hue2
        }
    }
}

/// A small, curated set of gradients used when no photo artwork is selected.
struct ArtworkTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let hue1: Double
    let hue2: Double

    static let violet = ArtworkTheme(id: "violet", name: "Violet", hue1: 0.76, hue2: 0.64)

    static let presets: [ArtworkTheme] = [
        violet,
        ArtworkTheme(id: "blue", name: "Blue", hue1: 0.61, hue2: 0.53),
        ArtworkTheme(id: "aqua", name: "Aqua", hue1: 0.52, hue2: 0.45),
        ArtworkTheme(id: "green", name: "Green", hue1: 0.39, hue2: 0.30),
        ArtworkTheme(id: "orange", name: "Orange", hue1: 0.08, hue2: 0.01),
        ArtworkTheme(id: "pink", name: "Pink", hue1: 0.94, hue2: 0.84)
    ]
}

struct PlaylistArtworkIcon: Identifiable {
    let name: String
    let systemImage: String

    var id: String { systemImage }

    static let presets: [PlaylistArtworkIcon] = [
        PlaylistArtworkIcon(name: "Playlist", systemImage: "music.note.list"),
        PlaylistArtworkIcon(name: "Headphones", systemImage: "headphones"),
        PlaylistArtworkIcon(name: "Waveform", systemImage: "waveform"),
        PlaylistArtworkIcon(name: "Guitars", systemImage: "guitars"),
        PlaylistArtworkIcon(name: "Piano", systemImage: "pianokeys"),
        PlaylistArtworkIcon(name: "Speaker", systemImage: "hifispeaker.fill"),
        PlaylistArtworkIcon(name: "Driving", systemImage: "car.fill"),
        PlaylistArtworkIcon(name: "Night", systemImage: "moon.stars.fill"),
        PlaylistArtworkIcon(name: "Sun", systemImage: "sun.max.fill"),
        PlaylistArtworkIcon(name: "Energy", systemImage: "bolt.fill"),
        PlaylistArtworkIcon(name: "Favorites", systemImage: "heart.fill"),
        PlaylistArtworkIcon(name: "Sparkles", systemImage: "sparkles")
    ]
}
