import XCTest
@testable import ClaudeUsageKit

final class TokenHistoryTests: XCTestCase {
    private func fixtureEvents() throws -> [TokenEvent] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/tokens", withExtension: "jsonl"))
        return JSONLParser.events(fromTranscript: try String(contentsOf: url, encoding: .utf8))
    }

    // MARK: JSONLParser (A1)

    func testParsesAssistantTokenEvents() throws {
        let events = try fixtureEvents()
        XCTAssertEqual(events.count, 3)   // 3 assistant turns, user line skipped
        let first = events[0]
        XCTAssertEqual(first.model, "claude-opus-4-8")
        XCTAssertEqual(first.inputTokens, 100)
        XCTAssertEqual(first.outputTokens, 200)
        XCTAssertEqual(first.cacheReadTokens, 1000)
        XCTAssertEqual(first.cacheCreationTokens, 50)
        XCTAssertEqual(first.totalTokens, 1350)
        XCTAssertEqual(first.project, "alpha")
        XCTAssertEqual(first.cast, .opus)
    }

    // MARK: TokenHistory (A2)

    func testByDayBuckets() throws {
        let events = try fixtureEvents()
        let days = TokenHistory.byDay(events)
        XCTAssertEqual(days.count, 2)              // 2026-06-10 and 06-11
        // consumed = input+output+cacheCreation (cache reads excluded).
        // Day 1: opus 350 + sonnet 30 = 380; Day 2: 10.
        XCTAssertEqual(days[0].tokens, 380)
        XCTAssertEqual(days[1].tokens, 10)
    }

    func testByModelAndProject() throws {
        let events = try fixtureEvents()
        let byModel = TokenHistory.byModel(events)
        XCTAssertEqual(byModel["claude-opus-4-8"], 360)    // 350 + 10
        XCTAssertEqual(byModel["claude-sonnet-4-6"], 30)
        let byProject = TokenHistory.byProject(events)
        XCTAssertEqual(byProject["alpha"], 380)
        XCTAssertEqual(byProject["beta"], 10)
    }

    func testHeaviestDayAndTopProject() throws {
        let events = try fixtureEvents()
        XCTAssertEqual(TokenHistory.heaviestDay(events)?.tokens, 380)
        XCTAssertEqual(TokenHistory.topProject(events)?.project, "alpha")
        XCTAssertEqual(TokenHistory.total(events), 390)
    }

    // MARK: Timeframe + token filter (C1/C3)

    func testTimeframeSpansAndCases() {
        XCTAssertEqual(Timeframe.allCases.count, 4)
        XCTAssertEqual(Timeframe.day.span, 24 * 3600)
        XCTAssertEqual(Timeframe.week.span, 7 * 24 * 3600)
        XCTAssertEqual(Timeframe.month.span, 30 * 24 * 3600)
        XCTAssertEqual(Timeframe.quarter.span, 90 * 24 * 3600)
    }

    func testTokenEventTimeframeAndModelFilter() {
        let now = Date(timeIntervalSince1970: 100 * 24 * 3600)   // day 100
        func ev(_ daysAgo: Double, _ model: String) -> TokenEvent {
            TokenEvent(timestamp: now.addingTimeInterval(-daysAgo * 24 * 3600), model: model,
                       inputTokens: 1, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, project: "p")
        }
        let events = [ev(0.04, "claude-opus-4-8"), ev(10, "claude-sonnet-4-6"), ev(60, "claude-opus-4-8")]
        // 24h: only the ~1h-ago opus event.
        XCTAssertEqual(HistoryFilter.tokenEvents(events, timeframe: .day, cast: nil, now: now).count, 1)
        // 30d: the 1h + 10d events (60d excluded).
        XCTAssertEqual(HistoryFilter.tokenEvents(events, timeframe: .month, cast: nil, now: now).count, 2)
        // 90d + opus only: the 1h and 60d opus events.
        XCTAssertEqual(HistoryFilter.tokenEvents(events, timeframe: .quarter, cast: .opus, now: now).count, 2)
    }
}
