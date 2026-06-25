import Foundation

// MARK: - PersistedPlayback
/// Pure, Codable snapshot of the last playback position, persisted across launches so the
/// app can restore where the user left off.
struct PersistedPlayback: Codable, Equatable {
    let trackID: UUID
    let position: TimeInterval
}

// MARK: - PlaybackRestore
/// Pure resolution of a persisted snapshot against the current library.
enum PlaybackRestore {
    /// Returns the matching track and a clamped start position, or nil if the saved track
    /// no longer exists (deleted) or there is no snapshot.
    static func resolve(_ saved: PersistedPlayback?, in tracks: [Track]) -> (track: Track, position: TimeInterval)? {
        guard let saved, let track = tracks.first(where: { $0.id == saved.trackID }) else { return nil }
        // Clamp into the track; if duration is unknown (0) keep the raw position.
        let upperBound = track.duration > 0 ? track.duration : saved.position
        let clamped = min(max(0, saved.position), upperBound)
        return (track, clamped)
    }
}

// MARK: - SleepTimer
/// Pure countdown logic for the sleep timer, kept separate from the Timer side effect.
enum SleepTimer {
    /// Advances the remaining time by `delta` seconds. `fired` is true once it reaches zero.
    static func advance(remaining: TimeInterval, by delta: TimeInterval = 1) -> (next: TimeInterval, fired: Bool) {
        let next = remaining - delta
        return next <= 0 ? (0, true) : (next, false)
    }

    /// Selectable durations offered in the UI (minutes).
    static let presetMinutes: [Int] = [15, 30, 45, 60]
}

// MARK: - PlaybackSpeed
/// Pure helpers for the playback-rate control.
enum PlaybackSpeed {
    /// Selectable rates offered in the UI.
    static let options: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    static let `default`: Float = 1.0

    /// Compact label, e.g. "1x", "1.5x".
    static func label(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))x" : String(format: "%gx", rate)
    }
}
