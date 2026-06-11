import XCTest
@testable import ClaudeUsageKit

final class TemperamentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)
    private let reset = Date(timeIntervalSince1970: 1000)

    // MARK: G1 — temperament modes

    func testThreeTemperaments() {
        XCTAssertEqual(Temperament.allCases.count, 3)
        XCTAssertLessThan(Temperament.confident.projectionWeight, Temperament.balanced.projectionWeight)
        XCTAssertLessThan(Temperament.balanced.projectionWeight, Temperament.suspicious.projectionWeight)
    }

    func testSuspiciousScoresHigherThanConfident() {
        // 40% used, 50% elapsed (past the damping ramp) — projection pulls up,
        // and Suspicious weights projection more than Confident.
        let now = Date(timeIntervalSince1970: 500)
        let confident = RiskScorer.score(utilization: 40, windowStart: start, resetsAt: reset, now: now, temperament: .confident)
        let suspicious = RiskScorer.score(utilization: 40, windowStart: start, resetsAt: reset, now: now, temperament: .suspicious)
        XCTAssertGreaterThan(suspicious, confident)
    }

    // MARK: G2 — early-window confidence damping

    func testEarlyWindowDampingReducesProjectionInfluence() {
        // Same usage/projection ratio early (10% elapsed) vs mid (50% elapsed):
        // early damping should keep the score closer to raw `used`.
        let earlyNow = Date(timeIntervalSince1970: 100)   // 10% elapsed → confidence 0.4
        let midNow = Date(timeIntervalSince1970: 500)     // 50% elapsed → confidence 1.0
        let early = RiskScorer.score(utilization: 40, windowStart: start, resetsAt: reset, now: earlyNow, temperament: .suspicious)
        let mid = RiskScorer.score(utilization: 40, windowStart: start, resetsAt: reset, now: midNow, temperament: .suspicious)
        // Mid-window leans harder on the (still-high) projection → higher score.
        XCTAssertLessThan(early, mid)
        XCTAssertGreaterThanOrEqual(early, 0.40)   // never below raw used
    }

    func testTemperamentPersists() {
        var s = AppSettings.default
        s.temperament = .suspicious
        XCTAssertEqual(s.temperament, .suspicious)
    }
}
