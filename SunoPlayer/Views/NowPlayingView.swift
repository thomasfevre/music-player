import SwiftUI

// MARK: - NowPlayingView
/// Full-screen now-playing experience with animated gradient artwork, seek bar, and controls.
struct NowPlayingView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Binding var isPresented: Bool

    // Drag-to-dismiss gesture
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    // Animated gradient hue shift
    @State private var gradientPhase: Double = 0

    // Seek-bar scrubbing: nil unless the user is actively dragging.
    @State private var scrubProgress: CGFloat?

    private var track: Track? { player.currentTrack }

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

                        // Secondary controls (shuffle, repeat, queue)
                        secondaryControls
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        // Drag-to-dismiss
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                        isDragging = true
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        isPresented = false
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                    isDragging = false
                }
        )
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: true)) {
                gradientPhase = 1.0
            }
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
            if let track {
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
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
        .shadow(
            color: (track?.gradientColors.first ?? .purple).opacity(0.5),
            radius: player.isPlaying ? 50 : 25,
            y: 12
        )
        .animation(.easeInOut(duration: 0.5), value: player.isPlaying)
        .scaleEffect(player.isPlaying ? 1.0 : 0.93)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
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

            // Heart / favourite (cosmetic for now)
            Button {} label: {
                Image(systemName: "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
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

            // Track count indicator
            if let track, let idx = player.activeQueue.firstIndex(of: track) {
                Text("\(idx + 1) / \(player.activeQueue.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.35))
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
