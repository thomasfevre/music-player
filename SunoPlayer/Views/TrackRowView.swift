import SwiftUI
import Combine

// MARK: - TrackRowView
/// A single row in the library list, showing gradient artwork, title, artist, and duration.
struct TrackRowView: View {
    let track: Track
    let isActive: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Artwork thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: track.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .shadow(color: track.gradientColors[0].opacity(0.5), radius: 8, y: 4)

                if isPlaying {
                    // Animated equalizer bars
                    EqualizerBarsView()
                        .frame(width: 24, height: 20)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            // Title & Artist
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .white.opacity(0.9))
                    .lineLimit(1)

                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(DurationFormatter.format(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: track.gradientColors.map { $0.opacity(0.5) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.04))
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - EqualizerBarsView
/// Animated bars that simulate an active equalizer.
struct EqualizerBarsView: View {
    @State private var heights: [CGFloat] = [0.4, 0.8, 0.5, 0.9, 0.3]
    @State private var timer: AnyCancellable?

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: heights[i] * 20)
                    .animation(
                        .easeInOut(duration: 0.18 + Double(i) * 0.03),
                        value: heights[i]
                    )
            }
        }
        // Drive the timer only while the row is on-screen, so off-screen rows don't tick.
        .onAppear {
            timer = Timer.publish(every: 0.18, on: .main, in: .common)
                .autoconnect()
                .sink { _ in heights = heights.map { _ in CGFloat.random(in: 0.25...1.0) } }
        }
        .onDisappear {
            timer?.cancel()
            timer = nil
        }
    }
}
