import XCTest
@testable import TokenMukbangKit

final class SessionTests: XCTestCase {
    func testParsePsOutputKeepsOnlyClaude() {
        let out = """
        21399 ttys016 claude
        62434 ttys017 /opt/homebrew/bin/claude
         1395 ??      chrome-native-host
        99999 ttys099 claude-extra
        """
        let parsed = SessionDetector.parsePsOutput(out)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].pid, 21399)
        XCTAssertEqual(parsed[0].tty, "ttys016")
        XCTAssertEqual(parsed[1].pid, 62434)
        XCTAssertEqual(parsed[1].tty, "ttys017")
    }

    func testEncodeProjectDir() {
        XCTAssertEqual(
            SessionDetector.encodeProjectDir("/Users/wogus/Project/njtransit"),
            "-Users-wogus-Project-njtransit"
        )
        XCTAssertEqual(
            SessionDetector.encodeProjectDir("/Users/wogus/Project/wogus/claude-usage-widget"),
            "-Users-wogus-Project-wogus-claude-usage-widget"
        )
    }

    func testContextFractionFromTranscriptFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/transcript", withExtension: "jsonl"))
        let parsed = try XCTUnwrap(ContextFraction.parseTranscript(try String(contentsOf: url, encoding: .utf8)))
        // Last assistant turn: 131 + 569 + 300000 = 300700 tokens.
        XCTAssertEqual(parsed.tokens, 300_700)
        // >200k → 1M window inferred.
        XCTAssertEqual(parsed.window, 1_000_000)
        XCTAssertEqual(parsed.model, "claude-opus-4-8")

        let fraction = try XCTUnwrap(ContextFraction.fraction(transcriptPath: url.path))
        XCTAssertEqual(fraction, 0.3007, accuracy: 0.0001)
    }

    func testContextTokensSumsCacheFields() {
        let usage: [String: Any] = [
            "input_tokens": 10,
            "cache_creation_input_tokens": 20,
            "cache_read_input_tokens": 70,
            "output_tokens": 999,
        ]
        XCTAssertEqual(ContextFraction.contextTokens(fromUsage: usage), 100)
    }

    func testWindowSizeHeuristic() {
        XCTAssertEqual(ContextFraction.windowSize(forTokens: 50_000, model: "claude-opus-4-8"), 200_000)
        XCTAssertEqual(ContextFraction.windowSize(forTokens: 300_000, model: "claude-opus-4-8"), 1_000_000)
        XCTAssertEqual(ContextFraction.windowSize(forTokens: 5_000, model: "claude-opus-4-8[1m]"), 1_000_000)
    }
}
