import XCTest
@testable import TokenMukbangKit

final class RiskTests: XCTestCase {
    func testLevelThresholds() {
        XCTAssertEqual(RiskScorer.level(forScore: 0.10), .calm)
        XCTAssertEqual(RiskScorer.level(forScore: 0.50), .watch)
        XCTAssertEqual(RiskScorer.level(forScore: 0.80), .warning)
        XCTAssertEqual(RiskScorer.level(forScore: 0.95), .critical)
    }

    func testColorsAreDistinct() {
        let hexes = Set(RiskLevel.allCases.map(\.hex))
        XCTAssertEqual(hexes.count, RiskLevel.allCases.count)
        for level in RiskLevel.allCases {
            XCTAssertTrue(level.hex.hasPrefix("#"))
            XCTAssertEqual(level.hex.count, 7)
        }
    }

    func testPacingRaisesScoreEarlyInWindow() {
        // 40% used but only 10% of the window elapsed → pacing pushes risk up.
        let start = Date(timeIntervalSince1970: 0)
        let reset = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 100) // 10% elapsed
        let score = RiskScorer.score(utilization: 40, windowStart: start, resetsAt: reset, now: now)
        XCTAssertGreaterThan(score, 0.40)
    }

    func testWithoutWindowStartFallsBackToAbsolute() {
        let reset = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 100)
        let score = RiskScorer.score(utilization: 72, resetsAt: reset, now: now)
        XCTAssertEqual(score, 0.72, accuracy: 0.0001)
    }
}
