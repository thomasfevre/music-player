import AVFoundation

/// Single owner of the playback audio-session configuration.
///
/// The category used to be set once in `SunoPlayerApp.init()` while activation happened
/// later in `AudioPlayerManager`. If the category was never applied (launch-time failure)
/// or the system reset the session, playback could be running under a session that is not
/// allowed to continue in the background. Applying an idempotent configuration right before
/// every activation keeps the session background-capable for the lifetime of the app.
enum AudioSessionController {
    static let options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]

    static func configure() throws {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback
                || session.mode != .default
                || !session.categoryOptions.contains(.allowBluetoothA2DP) else { return }
        try session.setCategory(.playback, mode: .default, options: options)
    }

    static func activate() throws {
        try configure()
        try AVAudioSession.sharedInstance().setActive(true)
    }
}
