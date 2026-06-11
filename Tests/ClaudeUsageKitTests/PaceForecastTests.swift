import XCTest
@testable import ClaudeUsageKit

final class PaceForecastTests: XCTestCase {
    // A 1000s window for easy arithmetic.
    private let start = Date(timeIntervalSince1970: 0)
    private let reset = Date(timeIntervalSince1970: 1000)

    func testOnTrackToFillBeforeResetReturnsHours() {
        // 50% used at 10% elapsed → burning ~5× the clock → fills well before reset.
        let now = Date(timeIntervalSince1970: 100)
        let hours = PaceForecast.hoursToFull(utilization: 50, windowStart: start, resetsAt: reset, now: now)
        XCTAssertNotNil(hours)
        XCTAssertGreaterThanOrEqual(hours!, 1)
    }

    func testSafePaceReturnsNil() {
        // 10% used at 90% elapsed → won't fill before reset.
        let now = Date(timeIntervalSince1970: 900)
        XCTAssertNil(PaceForecast.hoursToFull(utilization: 10, windowStart: start, resetsAt: reset, now: now))
    }

    func testAlreadyFullOrEmptyReturnsNil() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertNil(PaceForecast.hoursToFull(utilization: 0, windowStart: start, resetsAt: reset, now: now))
        XCTAssertNil(PaceForecast.hoursToFull(utilization: 100, windowStart: start, resetsAt: reset, now: now))
    }

    func testWindowDurations() {
        XCTAssertEqual(UsageWindowKind.fiveHour.duration, 5 * 3600)
        XCTAssertEqual(UsageWindowKind.sevenDay.duration, 7 * 24 * 3600)
        XCTAssertEqual(UsageWindowKind.sevenDaySonnet.duration, 7 * 24 * 3600)
    }
}
