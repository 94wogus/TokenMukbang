import XCTest
@testable import TokenMukbangKit

final class NotificationDeciderTests: XCTestCase {
    private let thresholds = RiskThresholds(warning: 70, critical: 90)
    private let allOn = NotificationSettings(
        fiveHour: true, sevenDay: true, sonnet: true,
        escalation: true, recovery: true, pacing: true, reset: true, extraCredit: true, tokenExpiry: true)

    private func window(_ kind: String, _ util: Double, resets: TimeInterval = 1000, pace: Int? = nil) -> UsageSnapshot.Window {
        UsageSnapshot.Window(kind: kind, label: kind, utilization: util,
                             resetsAt: Date(timeIntervalSince1970: resets),
                             riskHex: "#000", riskLabel: "x", paceWarningHours: pace)
    }
    private func snap(_ windows: [UsageSnapshot.Window], error: String? = nil) -> UsageSnapshot {
        UsageSnapshot(capturedAt: Date(timeIntervalSince1970: 0), planLabel: "Max",
                      windows: windows, sessions: [], error: error)
    }

    func testEscalationOnWarningCross() {
        let prev = snap([window("five_hour", 60)])
        let cur = snap([window("five_hour", 72)])
        let alerts = NotificationDecider.alerts(previous: prev, current: cur, settings: allOn, thresholds: thresholds)
        XCTAssertEqual(alerts.filter { $0.event == .escalation }.count, 1)
    }

    func testEscalationOnCriticalCross() {
        let alerts = NotificationDecider.alerts(previous: snap([window("five_hour", 80)]),
                                                current: snap([window("five_hour", 95)]),
                                                settings: allOn, thresholds: thresholds)
        XCTAssertTrue(alerts.contains { $0.event == .escalation && $0.body.contains("배 터") })
    }

    func testNoEscalationWhenAlreadyAbove() {
        // Already above warning last time → no repeat (debounce by edge).
        let alerts = NotificationDecider.alerts(previous: snap([window("five_hour", 75)]),
                                                current: snap([window("five_hour", 80)]),
                                                settings: allOn, thresholds: thresholds)
        XCTAssertTrue(alerts.filter { $0.event == .escalation }.isEmpty)
    }

    func testRecovery() {
        let alerts = NotificationDecider.alerts(previous: snap([window("five_hour", 75)]),
                                                current: snap([window("five_hour", 60)]),
                                                settings: allOn, thresholds: thresholds)
        XCTAssertEqual(alerts.filter { $0.event == .recovery }.count, 1)
    }

    func testReset() {
        let alerts = NotificationDecider.alerts(previous: snap([window("five_hour", 80, resets: 1000)]),
                                                current: snap([window("five_hour", 5, resets: 99999)]),
                                                settings: allOn, thresholds: thresholds)
        XCTAssertEqual(alerts.filter { $0.event == .reset }.count, 1)
    }

    func testPacing() {
        let alerts = NotificationDecider.alerts(previous: snap([window("five_hour", 40, pace: nil)]),
                                                current: snap([window("five_hour", 50, pace: 3)]),
                                                settings: allOn, thresholds: thresholds)
        XCTAssertEqual(alerts.filter { $0.event == .pacing }.count, 1)
    }

    func testTokenExpiry() {
        let alerts = NotificationDecider.alerts(previous: snap([], error: nil),
                                                current: snap([], error: "OAuth token expired — refresh it"),
                                                settings: allOn, thresholds: thresholds)
        XCTAssertEqual(alerts.filter { $0.event == .tokenExpiry }.count, 1)
    }

    func testEventToggleGatesEscalation() {
        var settings = allOn
        settings.escalation = false   // event type off
        let alerts = NotificationDecider.alerts(previous: snap([window("five_hour", 60)]),
                                                current: snap([window("five_hour", 75)]),
                                                settings: settings, thresholds: thresholds)
        XCTAssertTrue(alerts.filter { $0.event == .escalation }.isEmpty)
    }

    func testSurfaceToggleGates() {
        var settings = allOn
        settings.fiveHour = false   // 5h surface off
        let alerts = NotificationDecider.alerts(previous: snap([window("five_hour", 60)]),
                                                current: snap([window("five_hour", 75)]),
                                                settings: settings, thresholds: thresholds)
        XCTAssertTrue(alerts.isEmpty)
    }
}
