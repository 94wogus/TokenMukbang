import XCTest
@testable import TokenMukbangKit

final class RiskTests: XCTestCase {
    func testLevelThresholds() {
        XCTAssertEqual(RiskScorer.level(forScore: 0.10), .calm)
        XCTAssertEqual(RiskScorer.level(forScore: 0.50), .watch)
        XCTAssertEqual(RiskScorer.level(forScore: 0.80), .warning)
        XCTAssertEqual(RiskScorer.level(forScore: 0.95), .critical)
    }

    func testCustomThresholdsMoveTheBands() {
        // A score of 0.55: warning at 50 → already "warning"; default 70 → only "watch".
        let strict = RiskThresholds(warning: 50, critical: 70)
        XCTAssertEqual(RiskScorer.level(forScore: 0.55, thresholds: strict), .warning)
        XCTAssertEqual(RiskScorer.level(forScore: 0.55, thresholds: .default), .watch)
        // Critical band follows the setting too: 0.75 ≥ 70 → critical when strict.
        XCTAssertEqual(RiskScorer.level(forScore: 0.75, thresholds: strict), .critical)
        XCTAssertEqual(RiskScorer.level(forScore: 0.75, thresholds: .default), .warning)
    }

    func testThresholdsFlowThroughPacingLevel() {
        // Pacing-aware level honors custom thresholds end-to-end. 50% used at 50%
        // elapsed projects to 100% → score ≈ 0.70. The *same* score lands on a
        // different level depending on the user's thresholds.
        let start = Date(timeIntervalSince1970: 0)
        let reset = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 500)
        func level(_ t: RiskThresholds) -> RiskLevel {
            RiskScorer.level(utilization: 50, windowStart: start, resetsAt: reset, now: now, thresholds: t)
        }
        XCTAssertEqual(level(.default), .warning)                              // 0.70 ≥ 70/100
        XCTAssertEqual(level(RiskThresholds(warning: 45, critical: 60)), .critical) // 0.70 ≥ 60/100
    }

    func testSnapshotRecolorReclassifiesWindows() {
        let win = UsageSnapshot.Window(
            kind: UsageWindowKind.fiveHour.rawValue, label: "5h", utilization: 50,
            resetsAt: Date(timeIntervalSince1970: 1_000_000),
            riskHex: RiskLevel.watch.hex, riskLabel: "Watch", riskLevel: "watch")
        let snap = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_000_000 - 18_000), // 5h window just opened → score ≈ util/100
            planLabel: nil, windows: [win], sessions: [], error: nil)
        let recolored = snap.recolored(thresholds: RiskThresholds(warning: 40, critical: 60))
        XCTAssertEqual(recolored.windows.first?.riskLevel, "warning")
        XCTAssertEqual(recolored.windows.first?.riskHex, RiskLevel.warning.hex)
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
