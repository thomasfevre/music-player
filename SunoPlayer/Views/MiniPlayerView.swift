import SwiftUI

// MARK: - MiniPlayerView
/// Compact player bar floating at the bottom of the library. Tapping opens NowPlayingView.
struct MiniPlayerView: View {
    @EnvironmentObject var library: MusicLibraryManager
    @EnvironmentObject var player: AudioPlayerManager
    @Binding var showNowPlaying: Bool

    @State private var isAnimatingArt = false

    private var track: Track? {
        guard let current = player.currentTrack else { return nil }
        return library.tracks.first { $0.id == current.id } ?? current
    }

    var body: some View {
        HStack(spacing: 14) {
            // Artwork
            if let track {
                TrackArtworkView(track: track, size: 44, cornerRadius: 8)
                    .shadow(color: track.gradientColors.first?.opacity(0.5) ?? .clear, radius: 8, y: 2)
                    .scaleEffect(isAnimatingArt && player.isPlaying ? 1.04 : 1.0)
                    .animation(
                        player.isPlaying
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: isAnimatingArt
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
            }
            .onAppear { isAnimatingArt = true }

            // Title & Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(track?.displayArtist ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            // Controls
            HStack(spacing: 20) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    player.playPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            // Liquid glass background
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showNowPlaying = true
        }
        // Progress line at bottom of mini player
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                let progress = min(max(player.duration > 0 ? player.currentTime / player.duration : 0, 0), 1)
                HStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: track?.gradientColors ?? [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(progress), height: 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
        }
    }
}
