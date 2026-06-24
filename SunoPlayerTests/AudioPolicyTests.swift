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
}
