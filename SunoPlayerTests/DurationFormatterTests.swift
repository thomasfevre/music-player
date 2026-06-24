import XCTest
@testable import SunoPlayer

final class DurationFormatterTests: XCTestCase {
    func testZero() { XCTAssertEqual(DurationFormatter.format(0), "0:00") }
    func testNegativeClampsToZero() { XCTAssertEqual(DurationFormatter.format(-5), "0:00") }
    func testNaN() { XCTAssertEqual(DurationFormatter.format(.nan), "0:00") }
    func testInfinite() { XCTAssertEqual(DurationFormatter.format(.infinity), "0:00") }
    func testSecondsPadding() { XCTAssertEqual(DurationFormatter.format(5), "0:05") }
    func testMinutesAndSeconds() { XCTAssertEqual(DurationFormatter.format(125), "2:05") }
    func testExactlyOneMinute() { XCTAssertEqual(DurationFormatter.format(60), "1:00") }
    func testHourBoundary() { XCTAssertEqual(DurationFormatter.format(3600), "1:00:00") }
    func testHoursMinutesSeconds() { XCTAssertEqual(DurationFormatter.format(3661), "1:01:01") }
    func testTruncatesFractional() { XCTAssertEqual(DurationFormatter.format(59.9), "0:59") }
}
