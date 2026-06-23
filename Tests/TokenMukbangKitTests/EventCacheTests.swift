import XCTest
@testable import TokenMukbangKit

final class EventCacheTests: XCTestCase {
    private var home: URL!
    private var cacheDir: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("evcache-\(UUID().uuidString)", isDirectory: true)
        home = base.appendingPathComponent(".claude", isDirectory: true)
        cacheDir = base.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("projects/proj-a", isDirectory: true),
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    /// One assistant turn line the parser accepts.
    private func line(ts: String, input: Int, output: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","cwd":"/Users/me/proj-a","message":{"model":"claude-opus-4-8","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
    }

    private func write(_ rel: String, _ text: String) throws {
        let url = home.appendingPathComponent("projects/\(rel)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadEvents() -> [TokenEvent] {
        EventCache.allEvents(claudeHome: home.path, cacheDirectory: cacheDir)
    }

    func testParsesAndWritesCache() throws {
        try write("proj-a/s1.jsonl", line(ts: "2026-06-20T10:00:00.000+00:00", input: 100, output: 50))
        let events = loadEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 100)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: cacheDir.appendingPathComponent(EventCache.fileName).path))
    }

    func testCacheHitReturnsSameEvents() throws {
        try write("proj-a/s1.jsonl", line(ts: "2026-06-20T10:00:00.000+00:00", input: 100, output: 50))
        let first = loadEvents()
        // Second run (file unchanged) must return identical events from the cache.
        let second = loadEvents()
        XCTAssertEqual(first, second)
        XCTAssertEqual(second.count, 1)
    }

    func testChangedFileReparses() throws {
        try write("proj-a/s1.jsonl", line(ts: "2026-06-20T10:00:00.000+00:00", input: 100, output: 50))
        _ = loadEvents()
        // Append a second turn (size + mtime change) → re-parsed → 2 events.
        let two = line(ts: "2026-06-20T10:00:00.000+00:00", input: 100, output: 50)
            + "\n" + line(ts: "2026-06-20T11:00:00.000+00:00", input: 200, output: 80)
        try write("proj-a/s1.jsonl", two)
        let events = loadEvents()
        XCTAssertEqual(events.count, 2)
    }

    func testNewAndDeletedFiles() throws {
        try write("proj-a/s1.jsonl", line(ts: "2026-06-20T10:00:00.000+00:00", input: 100, output: 50))
        try write("proj-a/s2.jsonl", line(ts: "2026-06-20T12:00:00.000+00:00", input: 300, output: 90))
        XCTAssertEqual(loadEvents().count, 2)
        // Delete one file → cache drops it, total reflects only the remaining file.
        try FileManager.default.removeItem(at: home.appendingPathComponent("projects/proj-a/s2.jsonl"))
        XCTAssertEqual(loadEvents().count, 1)
    }

    func testTokenEventCodableRoundTrip() throws {
        let e = TokenEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000), model: "claude-opus-4-8",
                           inputTokens: 1, outputTokens: 2, cacheReadTokens: 3, cacheCreationTokens: 4,
                           project: "p")
        let back = try JSONDecoder().decode(TokenEvent.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(e, back)
    }
}
