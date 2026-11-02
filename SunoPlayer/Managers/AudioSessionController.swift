import AVFoundation

/// Single owner of the playback audio-session configuration.
///
/// Category changes are only safe while the session is inactive: applying them to a live
/// session can fail with `kAudioSessionNoError`-style parameter errors (OSStatus -50) and
/// leave playback unable to start. The configuration is therefore applied once, retried on
/// the next activation if it failed, and re-applied after the system resets audio services.
@MainActor
enum AudioSessionController {
    static let options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]

    private static var needsConfiguration = true
    private static var isActivated = false

    static func configure() throws {
        let session = AVAudioSession.sharedInstance()
        guard !isActivated else { return }
        guard needsConfiguration || session.category != .playback || session.mode != .default else { return }
        try session.setCategory(.playback, mode: .default, options: options)
        needsConfiguration = false
    }

    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try configure()
            try session.setActive(true)
        } catch {
            // A session wedged by a failed category change (OSStatus -50) cannot be
            // activated as-is. Release it, forget the cached configuration, and retry once.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            isActivated = false
            needsConfiguration = true
            try configure()
            try session.setActive(true)
        }
        isActivated = true
    }

    /// The system deactivated the session (interruption, route loss, background policy).
    static func sessionBecameInactive() {
        isActivated = false
    }

    /// The system forgot the session's configuration; re-apply it before the next activation.
    static func sessionWasReset() {
        isActivated = false
        needsConfiguration = true
    }
}
