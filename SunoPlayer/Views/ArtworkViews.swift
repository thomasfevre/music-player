import PhotosUI
import SwiftUI

// MARK: - Reusable artwork

struct TrackArtworkView: View {
    let track: Track
    var size: CGFloat = 54
    var cornerRadius: CGFloat = 10
    var symbolName = "music.note"

    @StateObject private var artwork = ArtworkLoader()
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        Group {
            if track.usesListeningPoster {
                TrackListeningPosterArtworkView(
                    track: track,
                    listeningHistory: player.listeningHistory,
                    size: size,
                    cornerRadius: cornerRadius
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: track.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let image = artwork.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: symbolName)
                            .font(.system(size: max(16, size * 0.32), weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear { artwork.load(for: track) }
        .onChange(of: track.preferredArtworkFileName) {
            artwork.load(for: track)
        }
        .accessibilityHidden(true)
    }
}

/// A live editorial cover that turns existing listening history into a recognisable visual.
struct TrackListeningPosterArtworkView: View {
    let track: Track
    @ObservedObject var listeningHistory: ListeningHistoryStore
    var size: CGFloat
    var cornerRadius: CGFloat
    @AppStorage("statsCoverMetric") private var statsCoverMetricRaw = "plays"

    private var isCompact: Bool { size < 90 }
    private var summary: TrackListeningSummary { listeningHistory.summary(for: track.id) }
    private var plays: Int { summary.playCount }
    private var listenedMinutes: Int { Int(summary.totalListenedSeconds / 60) }
    private var headline: String {
        switch StatsCoverMetric(rawValue: statsCoverMetricRaw) ?? .plays {
        case .plays: return plays == 0 ? "NEW" : "\(plays)"
        case .minutes: return listenedMinutes == 0 ? "NEW" : "\(listenedMinutes)"
        case .skips: return "\(summary.earlySkipCount + summary.lateSkipCount)"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: track.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(.black.opacity(0.16))

            VStack(alignment: .leading, spacing: isCompact ? 2 : 9) {
                if !isCompact {
                    Text(plays == 0 ? "NEW IN YOUR LIBRARY" : "YOUR ROTATION")
                        .font(.system(size: size * 0.042, weight: .bold, design: .rounded))
                        .tracking(size * 0.008)
                        .foregroundStyle(.white.opacity(0.76))
                }

                Spacer(minLength: 0)

                Text(headline)
                    .font(.system(size: size * (isCompact ? 0.55 : 0.42), weight: .black, design: .rounded))
                    .minimumScaleFactor(0.45)
                    .foregroundStyle(.white)

                if !isCompact {
                    Rectangle()
                        .fill(.white.opacity(0.6))
                        .frame(height: 1)

                    HStack(spacing: 12) {
                        posterMetric("\(listenedMinutes) MIN", label: "LISTENED")
                        posterMetric("\(summary.earlySkipCount + summary.lateSkipCount)", label: "SKIPS")
                    }

                    Spacer(minLength: 0)

                    Text(track.displayArtist.uppercased())
                        .font(.system(size: size * 0.038, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(track.title.uppercased())
                        .font(.system(size: size * 0.052, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                }
            }
            .padding(size * (isCompact ? 0.13 : 0.09))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("Listening poster for \(track.title), \(plays) plays")
    }

    private func posterMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: size * 0.05, weight: .heavy, design: .rounded))
            Text(label)
                .font(.system(size: size * 0.027, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct PlaylistArtworkView: View {
    let playlist: Playlist
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12

    @StateObject private var artwork = ArtworkLoader()

    private var colors: [Color] {
        let hues = playlist.displayArtworkHues
        return [
            Color(hue: hues.0, saturation: 0.72, brightness: 0.84),
            Color(hue: hues.1, saturation: 0.82, brightness: 0.56)
        ]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image = artwork.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: playlist.displayArtworkIconName)
                    .font(.system(size: max(18, size * 0.34), weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .onAppear {
            artwork.load(fileName: playlist.artworkFileName, url: playlist.artworkURL)
        }
        .onChange(of: playlist.artworkFileName) {
            artwork.load(fileName: playlist.artworkFileName, url: playlist.artworkURL)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Track editor

struct TrackArtworkEditorView: View {
    let trackID: UUID

    @EnvironmentObject private var library: MusicLibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var previewVersion = 0
    @State private var isImportingPhoto = false

    private var track: Track? {
        library.tracks.first { $0.id == trackID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let track {
                        TrackArtworkView(track: track, size: 190, cornerRadius: 28, symbolName: "waveform")
                            .id(previewVersion)
                            .shadow(color: track.gradientColors[0].opacity(0.42), radius: 30, y: 12)
                            .padding(.top, 18)

                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Photo")
                            ArtworkPhotoPickerButton(isLoading: $isImportingPhoto) {
                                await library.setCustomArtwork($0, for: track)
                            } onSaved: {
                                previewVersion += 1
                            } onError: {
                                library.reportArtworkError($0)
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Color")
                            themeGrid { theme in
                                if library.setArtworkTheme(theme, for: track) {
                                    previewVersion += 1
                                }
                            }
                            .disabled(isImportingPhoto)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("Stats Cover")
                            Button {
                                if library.setListeningPosterArtwork(for: track) {
                                    previewVersion += 1
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.title3.weight(.semibold))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.usesListeningPoster ? "Listening Poster Selected" : "Use Listening Poster")
                                            .font(.headline)
                                        Text("Shows plays, listening time and skips")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if track.usesListeningPoster {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isImportingPhoto)
                        }

                        Button(role: .destructive) {
                            if library.resetArtwork(for: track) {
                                previewVersion += 1
                            }
                        } label: {
                            Label(
                                track.artworkFileName == nil ? "Restore Automatic Colors" : "Restore Original Artwork",
                                systemImage: "arrow.counterclockwise"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImportingPhoto)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Track Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isImportingPhoto)
                }
            }
            .alert(
                "Artwork Error",
                isPresented: Binding(
                    get: { library.lastError != nil },
                    set: { if !$0 { library.clearError() } }
                )
            ) {
                Button("OK") { library.clearError() }
            } message: {
                Text(library.lastError ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isImportingPhoto)
    }
}

// MARK: - Playlist editor

struct PlaylistArtworkEditorView: View {
    let playlistID: UUID

    @EnvironmentObject private var playlists: PlaylistManager
    @Environment(\.dismiss) private var dismiss
    @State private var previewVersion = 0
    @State private var isImportingPhoto = false

    private var playlist: Playlist? {
        playlists.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let playlist {
                        PlaylistArtworkView(playlist: playlist, size: 190, cornerRadius: 28)
                            .id(previewVersion)
                            .shadow(color: previewShadow(for: playlist), radius: 30, y: 12)
                            .padding(.top, 18)

                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Photo")
                            ArtworkPhotoPickerButton(isLoading: $isImportingPhoto) {
                                await playlists.setCustomArtwork($0, for: playlist)
                            } onSaved: {
                                previewVersion += 1
                            } onError: {
                                playlists.reportArtworkError($0)
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Icon")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                                spacing: 12
                            ) {
                                ForEach(PlaylistArtworkIcon.presets) { icon in
                                    Button {
                                        if playlists.setArtworkStyle(
                                            iconName: icon.systemImage,
                                            theme: selectedTheme(for: playlist),
                                            for: playlist
                                        ) {
                                            previewVersion += 1
                                        }
                                    } label: {
                                        Image(systemName: icon.systemImage)
                                            .font(.system(size: 21, weight: .medium))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity, minHeight: 52)
                                            .background(
                                                playlist.artworkFileName == nil &&
                                                playlist.displayArtworkIconName == icon.systemImage
                                                    ? Color.purple.opacity(0.38)
                                                    : Color.white.opacity(0.07),
                                                in: RoundedRectangle(cornerRadius: 12)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(icon.name)
                                }
                            }
                            .disabled(isImportingPhoto)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Background")
                            themeGrid { theme in
                                if playlists.setArtworkStyle(
                                    iconName: playlist.displayArtworkIconName,
                                    theme: theme,
                                    for: playlist
                                ) {
                                    previewVersion += 1
                                }
                            }
                            .disabled(isImportingPhoto)
                        }

                        Button(role: .destructive) {
                            if playlists.resetArtwork(for: playlist) {
                                previewVersion += 1
                            }
                        } label: {
                            Label("Restore Default Artwork", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImportingPhoto)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Playlist Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isImportingPhoto)
                }
            }
            .alert(
                "Artwork Error",
                isPresented: Binding(
                    get: { playlists.lastError != nil },
                    set: { if !$0 { playlists.clearError() } }
                )
            ) {
                Button("OK") { playlists.clearError() }
            } message: {
                Text(playlists.lastError ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isImportingPhoto)
    }

    private func selectedTheme(for playlist: Playlist) -> ArtworkTheme {
        let hues = playlist.displayArtworkHues
        return ArtworkTheme.presets.min {
            abs($0.hue1 - hues.0) + abs($0.hue2 - hues.1) <
                abs($1.hue1 - hues.0) + abs($1.hue2 - hues.1)
        } ?? .violet
    }

    private func previewShadow(for playlist: Playlist) -> Color {
        let hues = playlist.displayArtworkHues
        return Color(hue: hues.0, saturation: 0.72, brightness: 0.7).opacity(0.42)
    }

}

// MARK: - Editor components

private func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.headline)
        .foregroundStyle(.white)
}

private struct ArtworkPhotoPickerButton: View {
    @Binding var isLoading: Bool

    let save: (Data) async -> Bool
    let onSaved: () -> Void
    let onError: (String) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label(
                isLoading ? "Loading Photo…" : "Choose from Photos",
                systemImage: "photo.on.rectangle"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .disabled(isLoading)
        .onChange(of: selectedPhoto) {
            importSelectedPhoto()
        }
    }

    private func importSelectedPhoto() {
        guard let selectedPhoto else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                if await save(data) {
                    onSaved()
                }
            } catch {
                onError("The selected photo could not be loaded: \(error.localizedDescription)")
            }
        }
    }
}

private func themeGrid(action: @escaping (ArtworkTheme) -> Void) -> some View {
    LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
        spacing: 12
    ) {
        ForEach(ArtworkTheme.presets) { theme in
            Button {
                action(theme)
            } label: {
                VStack(spacing: 8) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: theme.hue1, saturation: 0.72, brightness: 0.86),
                                    Color(hue: theme.hue2, saturation: 0.82, brightness: 0.58)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    Text(theme.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Settings and listening metrics

struct SettingsView: View {
    @EnvironmentObject private var library: MusicLibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var defaultStyle = ArtworkPreferences.defaultStyle
    @State private var usesUniqueColors = ArtworkPreferences.usesUniqueColors
    @State private var showsListeningBadges = ArtworkPreferences.showsListeningBadges
    @State private var statsCoverMetric = ArtworkPreferences.statsCoverMetric
    @State private var crossfadeDuration = PlaybackPreferences.crossfadeDuration
    @State private var showApplyConfirmation = false
    @State private var showListeningStats = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("New track artwork", selection: $defaultStyle) {
                        ForEach(DefaultTrackArtworkStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Toggle("Use a stable unique color per generated cover", isOn: $usesUniqueColors)
                    Picker("Stats Poster headline", selection: $statsCoverMetric) {
                        ForEach(StatsCoverMetric.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Apply these settings to all tracks") { showApplyConfirmation = true }
                } header: {
                    Text("Artwork")
                } footer: {
                    Text("Photos are kept safely. This only changes the displayed artwork style.")
                }

                Section("Listening") {
                    Toggle("Show listening badges in lists", isOn: $showsListeningBadges)
                    NavigationLink {
                        ListeningStatsView()
                            .environmentObject(library)
                            .environmentObject(player)
                    } label: {
                        Label("Listening Stats", systemImage: "chart.bar.xaxis")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Crossfade")
                            Spacer()
                            Text(crossfadeDuration == 0 ? "Off" : "\(Int(crossfadeDuration)) sec")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $crossfadeDuration, in: 0...8, step: 1)
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Overlaps the end of one track with the beginning of the next. Short tracks use a shorter transition automatically.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(isPresented: $showListeningStats) {
                ListeningStatsView()
                    .environmentObject(library)
                    .environmentObject(player)
            }
            .onChange(of: defaultStyle) { ArtworkPreferences.defaultStyle = defaultStyle }
            .onChange(of: usesUniqueColors) { ArtworkPreferences.usesUniqueColors = usesUniqueColors }
            .onChange(of: showsListeningBadges) { ArtworkPreferences.showsListeningBadges = showsListeningBadges }
            .onChange(of: statsCoverMetric) { ArtworkPreferences.statsCoverMetric = statsCoverMetric }
            .onChange(of: crossfadeDuration) { PlaybackPreferences.crossfadeDuration = crossfadeDuration }
            .confirmationDialog("Apply Artwork Settings?", isPresented: $showApplyConfirmation) {
                Button("Apply to \(library.tracks.count) Tracks") { _ = library.applyArtworkPreferencesToAllTracks() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your custom photos remain available.")
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("UITEST_STATS") {
                    showListeningStats = true
                }
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }
}

struct ListeningStatsView: View {
    @EnvironmentObject private var library: MusicLibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    private var summaries: [UUID: TrackListeningSummary] { player.listeningHistory.history.summaries }
    private var totalPlays: Int { summaries.values.reduce(0) { $0 + $1.playCount } }
    private var totalMinutes: Int { Int(summaries.values.reduce(0) { $0 + $1.totalListenedSeconds } / 60) }
    private var totalSkips: Int { summaries.values.reduce(0) { $0 + $1.earlySkipCount + $1.lateSkipCount } }
    private var topTracks: [(track: Track, summary: TrackListeningSummary)] {
        library.tracks.compactMap { track in
            guard let summary = summaries[track.id], summary.playCount > 0 else { return nil }
            return (track, summary)
        }
        .sorted { $0.summary.playCount > $1.summary.playCount }
        .prefix(10)
        .map { $0 }
    }

    var body: some View {
        List {
            Section("Your listening") {
                LabeledContent("Plays", value: "\(totalPlays)")
                LabeledContent("Listening time", value: "\(totalMinutes) min")
                LabeledContent("Skips", value: "\(totalSkips)")
            }
            Section("Most played") {
                if topTracks.isEmpty {
                    Text("Play a few tracks to see your listening patterns here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topTracks, id: \.track.id) { item in
                        HStack(spacing: 12) {
                            TrackArtworkView(track: item.track, size: 38, cornerRadius: 9)
                            VStack(alignment: .leading) {
                                Text(item.track.title).lineLimit(1)
                                Text(item.track.displayArtist).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(item.summary.playCount)").font(.headline.monospacedDigit())
                        }
                    }
                }
            }
        }
        .navigationTitle("Listening Stats")
    }
}
