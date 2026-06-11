import XCTest
@testable import ClaudeUsageKit

final class FileWatcherTests: XCTestCase {
    func testStartFailsForMissingFile() {
        let watcher = FileWatcher(path: "/nonexistent/\(UUID().uuidString)") {}
        XCTAssertFalse(watcher.start())
        watcher.stop()
    }

    func testFiresOnWrite() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tmk-watch-\(UUID().uuidString).txt")
        try "a".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let fired = expectation(description: "onChange fires")
        fired.assertForOverFulfill = false
        let watcher = FileWatcher(path: url.path) { fired.fulfill() }
        XCTAssertTrue(watcher.start())
        defer { watcher.stop() }

        // Mutate the watched file.
        try "ab".write(to: url, atomically: false, encoding: .utf8)
        wait(for: [fired], timeout: 3.0)
    }
}
