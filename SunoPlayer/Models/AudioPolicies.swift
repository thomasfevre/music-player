import AVFoundation

enum PlaybackPreferences {
    private static let crossfadeKey = "crossfadeDurationSeconds"

    static var crossfadeDuration: TimeInterval {
        get {
            guard UserDefaults.standard.object(forKey: crossfadeKey) != nil else { return 3 }
            return max(0, min(8, UserDefaults.standard.double(forKey: crossfadeKey)))
        }
        set { UserDefaults.standard.set(max(0, min(8, newValue)), forKey: crossfadeKey) }
    }
}

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

enum CrossfadePolicy {
    static func transitionLeadTime(duration: TimeInterval, configured: TimeInterval) -> TimeInterval {
        guard duration > 0, configured > 0 else { return 0 }
        return min(configured, duration * 0.25)
    }

    static func shouldBegin(
        position: TimeInterval,
        duration: TimeInterval,
        configured: TimeInterval,
        hasNextTrack: Bool,
        alreadyStarted: Bool
    ) -> Bool {
        guard hasNextTrack, !alreadyStarted else { return false }
        let lead = transitionLeadTime(duration: duration, configured: configured)
        return lead > 0 && position >= duration - lead
    }
}
