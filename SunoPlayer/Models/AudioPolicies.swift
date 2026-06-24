import AVFoundation

// MARK: - Audio session policies
/// Pure, testable decision logic for audio-session lifecycle events.
/// Kept free of player/state so it can be unit-tested without AVFoundation side effects.

enum AudioInterruptionPolicy {
    /// Resume playback after an interruption ends only if playback was active when it
    /// began AND the system says it is appropriate to resume.
    static func shouldResume(wasPlaying: Bool, options: AVAudioSession.InterruptionOptions) -> Bool {
        wasPlaying && options.contains(.shouldResume)
    }
}

enum AudioRoutePolicy {
    /// Pause when the previously active output device becomes unavailable
    /// (e.g. headphones unplugged), matching system audio behavior.
    static func shouldPause(reason: AVAudioSession.RouteChangeReason) -> Bool {
        reason == .oldDeviceUnavailable
    }
}
