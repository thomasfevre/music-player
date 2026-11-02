import AVFoundation

/// Owns the playback audio-session configuration and activation.
///
/// Normal activation must stay a plain `setActive(true)`: reconfiguring the category on a
/// live session can fail with OSStatus -50 and leave playback dead. The category is applied
/// once during launch and re-applied only through the recovery path.
@MainActor
enum AudioSessionController {
    static let options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]

    /// Launch-time configuration. Failure is not fatal: activation still has a fallback.
    static func configure() throws {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback || session.mode != .default else { return }
        try session.setCategory(.playback, mode: .default, options: options)
    }

    /// Plain activation, matching the behaviour that shipped. If the session is wedged,
    /// release it and retry once with a fresh configuration before giving up.
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        }
    }
}
