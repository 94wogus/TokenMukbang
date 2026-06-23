import XCTest
@testable import TokenMukbangKit

final class ValueTests: XCTestCase {
    private func ev(_ ts: Date, _ model: String, input: Int = 0, output: Int = 0,
                   cacheRead: Int = 0, cacheWrite: Int = 0) -> TokenEvent {
        TokenEvent(timestamp: ts, model: model, inputTokens: input, outputTokens: output,
                   cacheReadTokens: cacheRead, cacheCreationTokens: cacheWrite, project: "p")
    }

    // MARK: ModelPricing

    func testPricingByModelVersion() {
        XCTAssertEqual(ModelPricing.forModel("claude-opus-4-8")?.input, 5)
        XCTAssertEqual(ModelPricing.forModel("claude-opus-4-8")?.output, 25)
        XCTAssertEqual(ModelPricing.forModel("claude-opus-4-1-20250805")?.input, 15)   // older Opus
        XCTAssertEqual(ModelPricing.forModel("claude-opus-4-1-20250805")?.output, 75)
        XCTAssertEqual(ModelPricing.forModel("claude-sonnet-4-6")?.input, 3)
        XCTAssertEqual(ModelPricing.forModel("claude-haiku-4-5")?.input, 1)
        XCTAssertEqual(ModelPricing.forModel("claude-fable-5")?.output, 50)
        XCTAssertNil(ModelPricing.forModel("mock-claude"))
        XCTAssertNil(ModelPricing.forModel("<synthetic>"))
    }

    func testCostComponents() {
        let e = ev(Date(), "claude-opus-4-8", input: 1_000_000, output: 1_000_000,
                   cacheRead: 10_000_000, cacheWrite: 1_000_000)
        let c = try! XCTUnwrap(ModelPricing.cost(e))
        XCTAssertEqual(c.input, 5, accuracy: 1e-6)      // 1M × $5/1M
        XCTAssertEqual(c.output, 25, accuracy: 1e-6)    // 1M × $25/1M
        XCTAssertEqual(c.cacheWrite, 6.25, accuracy: 1e-6)  // 1M × $5 × 1.25
        XCTAssertEqual(c.cacheRead, 5, accuracy: 1e-6)  // 10M × $5 × 0.1
        XCTAssertEqual(c.total, 41.25, accuracy: 1e-6)
        XCTAssertNil(ModelPricing.cost(ev(Date(), "mock-claude", input: 999)))
    }

    // MARK: ValueEstimate

    func testBuildAggregatesAndSavings() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let events = [
            ev(start.addingTimeInterval(100), "claude-opus-4-8", input: 1_000_000, output: 1_000_000,
               cacheRead: 10_000_000, cacheWrite: 1_000_000),               // $41.25
            ev(start.addingTimeInterval(200), "claude-fable-5", output: 1_000_000),  // 1M × $50 = $50
            ev(start.addingTimeInterval(300), "mock-claude", input: 5_000_000),      // unpriced
        ]
        let v = ValueEstimate.build(events: events, periodStart: start, periodEnd: end)
        XCTAssertEqual(v.apiEquivalent, 91.25, accuracy: 1e-6)
        XCTAssertEqual(v.costExclCacheRead, 86.25, accuracy: 1e-6)   // 91.25 − $5 cache-read
        XCTAssertEqual(v.cacheReadCost, 5, accuracy: 1e-6)
        XCTAssertEqual(v.unpricedTokens, 5_000_000)                  // mock excluded from $ but counted
        XCTAssertEqual(v.lines.first?.name, "Fable")                // $50 > $41.25, heaviest first
        XCTAssertEqual(v.savings(subscription: 20), 71.25, accuracy: 1e-6)
        XCTAssertEqual(v.multiple(subscription: 20), 91.25 / 20, accuracy: 1e-6)
        XCTAssertEqual(v.multiple(subscription: 0), 0)              // no price set → 0
    }

    func testBuildExcludesOutOfPeriod() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let events = [
            ev(start.addingTimeInterval(-100), "claude-opus-4-8", output: 1_000_000),   // before
            ev(start.addingTimeInterval(100), "claude-opus-4-8", output: 1_000_000),    // in
            ev(end.addingTimeInterval(100), "claude-opus-4-8", output: 1_000_000),      // after
        ]
        let v = ValueEstimate.build(events: events, periodStart: start, periodEnd: end)
        XCTAssertEqual(v.apiEquivalent, 25, accuracy: 1e-6)   // only the one in-period event
    }

    func testFormatting() {
        XCTAssertEqual(ValueEstimate.dollars(16_619.4), "$16,619")
        XCTAssertEqual(ValueEstimate.multipleLabel(75.5), "76×")
        XCTAssertEqual(ValueEstimate.multipleLabel(3.43), "3.4×")
        XCTAssertEqual(ValueEstimate.multipleLabel(0), "—")
    }

    // MARK: AppSettings billing period + lenient decode

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testBillingPeriodStartRolling30() {
        var s = AppSettings.default; s.billingCycleDay = nil
        let now = date(2026, 6, 23)
        let start = s.billingPeriodStart(now: now, calendar: utc)
        XCTAssertEqual(start, utc.date(byAdding: .day, value: -30, to: now))
    }

    func testBillingPeriodStartCycleDay() {
        var s = AppSettings.default; s.billingCycleDay = 15
        // now after the 15th → period started on the 15th this month
        XCTAssertEqual(s.billingPeriodStart(now: date(2026, 6, 23), calendar: utc),
                       utc.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        // now before the 15th → period started on the 15th of the previous month
        XCTAssertEqual(s.billingPeriodStart(now: date(2026, 6, 10), calendar: utc),
                       utc.date(from: DateComponents(year: 2026, month: 5, day: 15)))
    }

    func testSettingsLenientDecodeDefaultsNewFields() throws {
        // An older settings.json with none of the new keys must still load (defaults applied).
        let json = "{\"theme\":\"charcoal\"}".data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(s.subscriptionMonthlyCost, AppSettings.defaultSubscriptionMonthlyCost)
        XCTAssertNil(s.billingCycleDay)
    }

    func testSettingsRoundTripNewFields() throws {
        var s = AppSettings.default
        s.subscriptionMonthlyCost = 220
        s.billingCycleDay = 7
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.subscriptionMonthlyCost, 220)
        XCTAssertEqual(back.billingCycleDay, 7)
    }
}
