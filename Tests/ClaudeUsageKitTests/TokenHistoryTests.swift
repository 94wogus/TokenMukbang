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
        // Day 1: 1350 (opus) + 130 (sonnet) = 1480; Day 2: 50.
        XCTAssertEqual(days[0].tokens, 1480)
        XCTAssertEqual(days[1].tokens, 50)
    }

    func testByModelAndProject() throws {
        let events = try fixtureEvents()
        let byModel = TokenHistory.byModel(events)
        XCTAssertEqual(byModel["claude-opus-4-8"], 1400)   // 1350 + 50
        XCTAssertEqual(byModel["claude-sonnet-4-6"], 130)
        let byProject = TokenHistory.byProject(events)
        XCTAssertEqual(byProject["alpha"], 1480)
        XCTAssertEqual(byProject["beta"], 50)
    }

    func testHeaviestDayAndTopProject() throws {
        let events = try fixtureEvents()
        XCTAssertEqual(TokenHistory.heaviestDay(events)?.tokens, 1480)
        XCTAssertEqual(TokenHistory.topProject(events)?.project, "alpha")
        XCTAssertEqual(TokenHistory.total(events), 1530)
    }
}
