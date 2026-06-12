import XCTest
@testable import TokenMukbangKit

final class MukbangTests: XCTestCase {
    // MARK: MukbangZone (T1.1)

    func testZoneBoundaries() {
        XCTAssertEqual(MukbangZone.forUtilization(0), .tasting)
        XCTAssertEqual(MukbangZone.forUtilization(24.9), .tasting)
        XCTAssertEqual(MukbangZone.forUtilization(25), .cruising)
        XCTAssertEqual(MukbangZone.forUtilization(59.9), .cruising)
        XCTAssertEqual(MukbangZone.forUtilization(60), .overeating)
        XCTAssertEqual(MukbangZone.forUtilization(84.9), .overeating)
        XCTAssertEqual(MukbangZone.forUtilization(85), .inhaling)
        XCTAssertEqual(MukbangZone.forUtilization(99.9), .inhaling)
        XCTAssertEqual(MukbangZone.forUtilization(100), .finished)
    }

    func testEveryZoneHasFaceLabelBowls() {
        for zone in MukbangZone.allCases {
            XCTAssertFalse(zone.restingFace.isEmpty)
            XCTAssertFalse(zone.label.isEmpty)
            XCTAssertFalse(zone.bowls.isEmpty)
        }
    }

    func testChewFramesNonEmptyAndFasterWhenRiskier() {
        for zone in MukbangZone.allCases {
            XCTAssertFalse(MukbangFace.chewFrames(for: zone).isEmpty, "\(zone) has no frames")
        }
        // Active-eating zones chew, and riskier = shorter interval.
        XCTAssertGreaterThan(MukbangFace.chewInterval(for: .tasting),
                             MukbangFace.chewInterval(for: .inhaling))
        XCTAssertEqual(MukbangFace.chewInterval(for: .finished), 0.0)
    }

    func testMenuBarTextHasFaceAndPercent() {
        let text = MukbangFace.menuBarText(utilization: 42)
        XCTAssertTrue(text.contains("42%"))
        XCTAssertTrue(text.contains(MukbangZone.cruising.restingFace))
    }

    func testMenuBarTextUsesChewFrameAndPadsFixedWidth() {
        let frame = "( o⊂●"
        let text = MukbangFace.menuBarText(utilization: 42, chewFrame: frame)
        XCTAssertTrue(text.contains(frame))
        XCTAssertTrue(text.contains("42%"))
        // Short faces are padded so the menu bar keeps a stable width.
        XCTAssertTrue(text.hasPrefix(frame.padding(toLength: 9, withPad: " ", startingAt: 0)))
    }

    // MARK: MukbangCopy (T1.2) — POV must not break

    func testHeadlineUsesWansik() {
        XCTAssertEqual(MukbangCopy.headline(utilization: 80), "80% 완식")
    }

    func testResetUsesDigestion() {
        let now = Date(timeIntervalSince1970: 0)
        let reset = MukbangCopy.reset(to: Date(timeIntervalSince1970: 8040), from: now)
        XCTAssertTrue(reset.contains("소화 중"))
        XCTAssertTrue(reset.contains("2h 14m"))
    }

    func testEventCopy() {
        XCTAssertTrue(MukbangCopy.event(.finished).contains("잘 먹었습니다"))
        XCTAssertTrue(MukbangCopy.event(.spoonDropped).contains("숟가락"))
        XCTAssertTrue(MukbangCopy.event(.freshTable).contains("새 상"))
        XCTAssertTrue(MukbangCopy.event(.paceWarning(hoursToFull: 3)).contains("3시간"))
        XCTAssertTrue(MukbangCopy.event(.backToKitchen).contains("주방"))
        XCTAssertTrue(MukbangCopy.status(for: .inhaling).contains("빨간불"))
    }

    // MARK: ModelCast (T1.3)

    func testModelCastMapping() {
        XCTAssertEqual(ModelCast.forModel("claude-opus-4-8"), .opus)
        XCTAssertEqual(ModelCast.forModel("seven_day_sonnet"), .sonnet)
        XCTAssertEqual(ModelCast.forModel("claude-haiku-4-5"), .haiku)
        // Fable 5 must map (was previously unmapped → 24% of recent tokens invisible).
        XCTAssertEqual(ModelCast.forModel("claude-fable-5"), .fable)
        XCTAssertNil(ModelCast.forModel("five_hour"))
        XCTAssertNil(ModelCast.forModel("<synthetic>"))
        XCTAssertEqual(ModelCast.allCases.count, 4)   // opus/sonnet/haiku/fable
        XCTAssertEqual(ModelCast.opus.label, "대식가")
        XCTAssertEqual(ModelCast.haiku.label, "소식좌")
        XCTAssertEqual(ModelCast.fable.modelName, "Fable")
        for c in ModelCast.allCases {
            XCTAssertFalse(c.face.isEmpty)
            XCTAssertFalse(c.modelName.isEmpty)
        }
    }
}
