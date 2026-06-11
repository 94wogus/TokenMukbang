import XCTest
@testable import ClaudeUsageKit

final class PacingCalculatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)
    private let reset = Date(timeIntervalSince1970: 1000)

    func testEquilibriumIsElapsedFraction() {
        XCTAssertEqual(PacingCalculator.equilibrium(windowStart: start, resetsAt: reset,
                                                    now: Date(timeIntervalSince1970: 500)), 50, accuracy: 0.001)
        XCTAssertEqual(PacingCalculator.equilibrium(windowStart: start, resetsAt: reset,
                                                    now: Date(timeIntervalSince1970: 0)), 0, accuracy: 0.001)
        XCTAssertEqual(PacingCalculator.equilibrium(windowStart: start, resetsAt: reset,
                                                    now: Date(timeIntervalSince1970: 1000)), 100, accuracy: 0.001)
    }

    func testDeltaAndAheadOfPace() {
        let now = Date(timeIntervalSince1970: 500)   // equilibrium = 50
        XCTAssertEqual(PacingCalculator.delta(utilization: 70, windowStart: start, resetsAt: reset, now: now), 20, accuracy: 0.001)
        XCTAssertTrue(PacingCalculator.isAheadOfPace(utilization: 70, windowStart: start, resetsAt: reset, now: now))
        XCTAssertFalse(PacingCalculator.isAheadOfPace(utilization: 30, windowStart: start, resetsAt: reset, now: now))
    }

    func testZeroWidthWindowIsSafe() {
        XCTAssertEqual(PacingCalculator.equilibrium(windowStart: start, resetsAt: start, now: start), 0)
    }
}
