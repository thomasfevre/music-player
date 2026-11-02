import XCTest
import AVFoundation
@testable import SunoPlayer

final class AudioPolicyTests: XCTestCase {

    func testResumeOnlyWhenPlayingAndShouldResume() {
        XCTAssertTrue(AudioInterruptionPolicy.shouldResume(wasPlaying: true, options: .shouldResume))
    }

    func testNoResumeWhenWasNotPlaying() {
        XCTAssertFalse(AudioInterruptionPolicy.shouldResume(wasPlaying: false, options: .shouldResume))
    }

    func testNoResumeWhenShouldResumeAbsent() {
        XCTAssertFalse(AudioInterruptionPolicy.shouldResume(wasPlaying: true, options: []))
    }

    func testPauseOnOldDeviceUnavailable() {
        XCTAssertTrue(AudioRoutePolicy.shouldPause(reason: .oldDeviceUnavailable))
    }

    func testNoPauseOnNewDeviceOrCategoryChange() {
        XCTAssertFalse(AudioRoutePolicy.shouldPause(reason: .newDeviceAvailable))
        XCTAssertFalse(AudioRoutePolicy.shouldPause(reason: .categoryChange))
        XCTAssertFalse(AudioRoutePolicy.shouldPause(reason: .routeConfigurationChange))
    }

    func testCrossfadeStartsInsideConfiguredWindow() {
        XCTAssertFalse(CrossfadePolicy.shouldBegin(position: 96.9, duration: 100, configured: 3, hasNextTrack: true, alreadyStarted: false))
        XCTAssertTrue(CrossfadePolicy.shouldBegin(position: 97, duration: 100, configured: 3, hasNextTrack: true, alreadyStarted: false))
    }

    func testCrossfadeLeadIsClampedForShortTracks() {
        XCTAssertEqual(CrossfadePolicy.transitionLeadTime(duration: 8, configured: 5), 2)
    }

    func testCrossfadeRequiresAnotherTrackAndRunsOnce() {
        XCTAssertFalse(CrossfadePolicy.shouldBegin(position: 99, duration: 100, configured: 3, hasNextTrack: false, alreadyStarted: false))
        XCTAssertFalse(CrossfadePolicy.shouldBegin(position: 99, duration: 100, configured: 3, hasNextTrack: true, alreadyStarted: true))
    }

    @MainActor
    func testAudioSessionConfiguresBackgroundCapablePlayback() throws {
        try AudioSessionController.configure()
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .default)
        XCTAssertTrue(session.categoryOptions.contains(.allowBluetoothA2DP))
        // Activating twice must not reconfigure a live session (OSStatus -50 regression).
        XCTAssertNoThrow(try AudioSessionController.activate())
        XCTAssertNoThrow(try AudioSessionController.activate())
    }
}
