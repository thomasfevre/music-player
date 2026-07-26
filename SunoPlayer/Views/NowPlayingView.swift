import SwiftUI

// MARK: - NowPlayingView
/// Full-screen now-playing experience with animated gradient artwork, seek bar, and controls.
struct NowPlayingView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var playlists: PlaylistManager
    @Binding var isPresented: Bool

    // Animated gradient hue shift
    @State private var gradientPhase: Double = 0

    // Seek-bar scrubbing: nil unless the user is actively dragging.
    @State private var scrubProgress: CGFloat?

    @StateObject private var artwork = ArtworkLoader()
    @State private var showQueue = false
    @State private var showArtworkEditor = false
    @State private var showResetLearningConfirmation = false

    private var track: Track? {
        guard let current = player.currentTrack else { return nil }
        return library.tracks.first { $0.id == current.id } ?? current
    }

    private var artSize: CGFloat {
        let width = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393
        return width - 56
    }

    /// Time shown next to the seek bar — follows the finger while scrubbing.
    private var displayedCurrentTime: Double {
        if let scrubProgress { return Double(scrubProgress) * player.duration }
        return player.currentTime
    }

    var body: some View {
        ZStack {
            // Full-bleed animated background
            animatedBackground

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(width: 40, height: 4)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 28) {
                        // Artwork
                        artworkCard
                            .padding(.horizontal, 28)

                        // Track info
                        trackInfo
                            .padding(.horizontal, 32)

                        // Seek bar
                        seekBar
                            .padding(.horizontal, 32)

                        // Playback controls
                        playbackControls
                            .padding(.horizontal, 24)

                        autoDJControls
                            .padding(.horizontal, 24)

                        // Volume
                        volumeBar
                            .padding(.horizontal, 32)

                        // Secondary controls (shuffle, repeat, queue)
                        secondaryControls
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        // Native interactive swipe-down dismiss from anywhere (sheet presentation).
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.black)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: true)) {
                gradientPhase = 1.0
            }
            artwork.load(for: track)
        }
        .onChange(of: track?.id) { artwork.load(for: track) }
        .onChange(of: track?.preferredArtworkFileName) { artwork.load(for: track) }
        .sheet(isPresented: $showQueue) {
            QueueView()
                .environmentObject(player)
                .environmentObject(playlists)
        }
        .sheet(isPresented: $showArtworkEditor) {
            if let track {
                TrackArtworkEditorView(trackID: track.id)
                    .environmentObject(library)
                    .environmentObject(player)
            }
        }
        .alert("Reset Auto-DJ Learning?", isPresented: $showResetLearningConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                player.resetListeningHistory()
            }
        } message: {
            Text("Your local listening history and feedback will be erased. Your music, playlists, and favorites will stay unchanged.")
        }
    }

    // MARK: - Background
    private var animatedBackground: some View {
        ZStack {
            Color.black

            if let track {
                // Inner glow from track's gradient
                RadialGradient(
                    colors: [
                        track.gradientColors[0].opacity(0.6),
                        track.gradientColors[1].opacity(0.3),
                        Color.clear
                    ],
                    center: .init(x: 0.3 + gradientPhase * 0.3, y: 0.25),
                    startRadius: 0,
                    endRadius: 380
                )

                RadialGradient(
                    colors: [
                        track.gradientColors[1].opacity(0.5),
                        Color.clear
                    ],
                    center: .init(x: 0.7 - gradientPhase * 0.2, y: 0.75),
                    startRadius: 0,
                    endRadius: 280
                )
            }

            // Frosted overlay
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.55))
        }
        .ignoresSafeArea()
    }

    // MARK: - Artwork Card
    private var artworkCard: some View {
        ZStack {
            if let track, track.usesListeningPoster {
                TrackListeningPosterArtworkView(
                    track: track,
                    listeningHistory: player.listeningHistory,
                    size: artSize,
                    cornerRadius: 28
                )
            } else if let image = artwork.image {
                // Real embedded cover art
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: artSize, height: artSize)
            } else if let track {
                // Main gradient artwork
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: track.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        // Sheen highlight
                        RoundedRectangle(cornerRadius: 28)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.25), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                    )

                // Music icon in center
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.6))
                        .scaleEffect(player.isPlaying ? 1.06 : 1.0)
                        .animation(
                            player.isPlaying
                                ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                                : .default,
                            value: player.isPlaying
                        )
                }
            }
        }
        .frame(width: artSize, height: artSize)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(
            color: (track?.gradientColors.first ?? .purple).opacity(0.5),
            radius: player.isPlaying ? 50 : 25,
            y: 12
        )
        .animation(.easeInOut(duration: 0.5), value: player.isPlaying)
        .scaleEffect(player.isPlaying ? 1.0 : 0.93)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
        .overlay(alignment: .topTrailing) {
            Button {
                showArtworkEditor = true
            } label: {
                Label("Edit Artwork", systemImage: "pencil")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize Track Artwork")
            .padding(12)
            .disabled(track == nil)
        }
    }

    // MARK: - Track Info
    private var trackInfo: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(track?.title ?? "")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(track?.displayArtist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()

            // Sleep timer
            Menu {
                if let remaining = player.sleepTimerRemaining {
                    Section("Sleeping in \(DurationFormatter.format(remaining))") {
                        Button("Cancel Timer", role: .destructive) { player.cancelSleepTimer() }
                    }
                }
                ForEach(SleepTimer.presetMinutes, id: \.self) { minutes in
                    Button("\(minutes) minutes") { player.startSleepTimer(minutes: minutes) }
                }
            } label: {
                let active = player.sleepTimerRemaining != nil
                Image(systemName: active ? "moon.fill" : "moon")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(active ? accentColor : .white.opacity(0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            // Heart / favourite
            Button {
                guard let track else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let isFavorite = library.toggleFavorite(track)
                player.recordFavoriteChange(for: track.id, isFavorite: isFavorite)
            } label: {
                let isFavorite = track.map(library.isFavorite) ?? false
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isFavorite ? .pink : .white.opacity(0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Auto-DJ
    @ViewBuilder
    private var autoDJControls: some View {
        if player.isAutoDJEnabled {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Auto-DJ", systemImage: "sparkles")
                            .font(.headline)
                        Text("Balanced · learns only on this iPhone")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Menu {
                        Button("Stop Auto-DJ", systemImage: "stop.fill") {
                            player.stopAutoDJ()
                        }
                        Button(
                            "Reset Learning",
                            systemImage: "arrow.counterclockwise",
                            role: .destructive
                        ) {
                            showResetLearningConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 44, height: 44)
                    }
                }

                if let reason = player.currentAutoDJReason, !reason.isEmpty {
                    Text("Why this track: \(reason)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                HStack(spacing: 10) {
                    autoDJFeedbackButton(
                        title: "Not for this session",
                        icon: "hand.thumbsdown",
                        positive: false
                    )
                    autoDJFeedbackButton(
                        title: "More like this",
                        icon: "hand.thumbsup",
                        positive: true
                    )
                }

                if !player.autoDJUpcomingRecommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("UP NEXT")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.4))

                        ForEach(player.autoDJUpcomingRecommendations.prefix(3), id: \.track.id) { recommendation in
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(accentColor)
                                    .frame(width: 32, height: 32)
                                    .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recommendation.track.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(recommendation.reasonText)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(accentColor.opacity(0.28), lineWidth: 1)
            }
        } else {
            VStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    _ = player.startAutoDJ(
                        library: library.tracks,
                        favoriteIDs: library.favoriteIDs,
                        playlistGroups: playlistTrackGroups
                    )
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "sparkles")
                            .font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Auto-DJ")
                                .font(.headline)
                            Text("Balanced picks from your downloaded music")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 66)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(track == nil || library.tracks.count < 2)
                .opacity(track == nil || library.tracks.count < 2 ? 0.45 : 1)

                Button {
                    showResetLearningConfirmation = true
                } label: {
                    Label("Reset Auto-DJ Learning", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func autoDJFeedbackButton(
        title: String,
        icon: String,
        positive: Bool
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            player.submitAutoDJFeedback(positive: positive)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var playlistTrackGroups: [[UUID]] {
        playlists.playlists.map {
            PlaylistResolver.tracks(
                for: $0,
                in: library.tracks,
                favoriteIDs: library.favoriteIDs
            ).map(\.id)
        }
    }

    // MARK: - Seek Bar
    private var seekBar: some View {
        VStack(spacing: 8) {
            // Track slider
            GeometryReader { geo in
                let liveProgress = player.duration > 0
                    ? CGFloat(player.currentTime / player.duration)
                    : 0
                let progress = min(max(scrubProgress ?? liveProgress, 0), 1)
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)

                    // Filled portion
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: track?.gradientColors ?? [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * progress), height: 4)

                    // Thumb
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .offset(x: max(0, geo.size.width * progress - 7))
                }
                .frame(height: 14)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Scrub locally only; committing every pixel forces expensive
                            // zero-tolerance seeks and causes audible stutter.
                            scrubProgress = max(0, min(1, value.location.x / geo.size.width))
                        }
                        .onEnded { value in
                            let ratio = max(0, min(1, value.location.x / geo.size.width))
                            player.seek(to: Double(ratio) * player.duration)
                            scrubProgress = nil
                        }
                )
            }
            .frame(height: 14)

            // Time labels
            HStack {
                Text(DurationFormatter.format(displayedCurrentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(DurationFormatter.format(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    // MARK: - Primary Playback Controls
    private var playbackControls: some View {
        HStack(spacing: 0) {
            // Previous
            controlButton(
                icon: "backward.fill",
                size: 28,
                opacity: 0.8
            ) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                player.previous()
            }

            Spacer()

            // Play / Pause (large)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.playPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .shadow(
                            color: (track?.gradientColors.first ?? .purple).opacity(0.55),
                            radius: 20,
                            y: 6
                        )

                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.black)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Next
            controlButton(
                icon: "forward.fill",
                size: 28,
                opacity: 0.8
            ) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                player.next()
            }
        }
    }

    // MARK: - Volume
    private var volumeBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
            #if targetEnvironment(simulator)
            // MPVolumeView is inert in the Simulator; show a representative slider so
            // App Store screenshots captured there render a real-looking volume control.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                    Capsule().fill(accentColor).frame(width: geo.size.width * 0.7, height: 4)
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .offset(x: geo.size.width * 0.7 - 7)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 28)
            #else
            SystemVolumeSlider(tint: accentColor)
                .frame(height: 28)
            #endif
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Secondary Controls (Shuffle, Repeat)
    private var secondaryControls: some View {
        HStack {
            // Shuffle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.toggleShuffle()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(player.shuffleEnabled ? accentColor : .white.opacity(0.45))
                    if player.shuffleEnabled {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }

            Spacer()

            // Playback speed
            Menu {
                ForEach(PlaybackSpeed.options, id: \.self) { rate in
                    Button {
                        player.setPlaybackRate(rate)
                    } label: {
                        HStack {
                            Text(PlaybackSpeed.label(rate))
                            if player.playbackRate == rate { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                let active = player.playbackRate != PlaybackSpeed.default
                Text(PlaybackSpeed.label(player.playbackRate))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(active ? accentColor : .white.opacity(0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            Spacer()

            // Track count indicator
            Button {
                showQueue = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 19, weight: .medium))
                    if let track, let idx = player.activeQueue.firstIndex(of: track) {
                        Text("\(idx + 1)/\(player.activeQueue.count)")
                            .font(.caption2.monospacedDigit())
                    }
                }
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 52, height: 44)
            }

            Spacer()

            // Repeat
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.cycleRepeatMode()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: player.repeatMode.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(player.repeatMode != .off ? accentColor : .white.opacity(0.45))
                    if player.repeatMode != .off {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Helpers

    private var accentColor: Color {
        track?.gradientColors.first ?? Color(hue: 0.75, saturation: 0.7, brightness: 0.9)
    }

    private func controlButton(
        icon: String,
        size: CGFloat,
        opacity: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(opacity))
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
