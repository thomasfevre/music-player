import Foundation

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
