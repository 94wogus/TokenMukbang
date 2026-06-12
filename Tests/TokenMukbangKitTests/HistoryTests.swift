import XCTest
@testable import TokenMukbangKit

final class HistoryTests: XCTestCase {
    private func tempStore() -> (HistoryStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tmk-history-\(UUID().uuidString)", isDirectory: true)
        return (HistoryStore(directory: dir, retention: 7 * 24 * 3600), dir)
    }

    private func sample(_ t: TimeInterval, _ u: [String: Double]) -> HistorySample {
        HistorySample(capturedAt: Date(timeIntervalSince1970: t), utilizations: u)
    }

    // MARK: HistoryStore (T3.1)

    func testAppendLoadRoundTrip() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 1000)
        store.append(sample(900, ["five_hour": 10]), now: now)
        store.append(sample(950, ["five_hour": 20]), now: now)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first?.utilizations["five_hour"], 10)
        XCTAssertEqual(loaded.last?.utilizations["five_hour"], 20)
    }

    func testPruneDropsOldSamples() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 10 * 24 * 3600)  // day 10
        store.append(sample(1, ["five_hour": 5]), now: now)    // ancient → pruned
        let retained = store.append(sample(now.timeIntervalSince1970 - 3600, ["five_hour": 50]), now: now)
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(store.load().count, 1)
    }

    func testRecordSkipsEmptySnapshot() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let empty = UsageSnapshot.failure("offline", at: Date(timeIntervalSince1970: 100))
        store.record(empty)
        XCTAssertTrue(store.load().isEmpty)
    }

    // MARK: Sparkline (T3.2)

    func testSparklineBuckets() {
        let now = Date(timeIntervalSince1970: 1000)
        // span 1000s, 10 buckets (100s each). Two samples in bucket 0, one in bucket 5.
        let samples = [
            sample(20, ["five_hour": 10]),    // bucket 0
            sample(80, ["five_hour": 30]),    // bucket 0 → avg 20
            sample(550, ["five_hour": 90]),   // bucket 5
        ]
        let series = Sparkline.series(from: samples, windowKind: "five_hour", span: 1000, buckets: 10, now: now)
        XCTAssertEqual(series.count, 10)
        XCTAssertEqual(series[0].value, 20, accuracy: 0.001)   // (10+30)/2
        XCTAssertEqual(series[5].value, 90, accuracy: 0.001)
        XCTAssertEqual(series[9].value, 0)                     // empty bucket
    }

    // MARK: HistoryFilter (T3.3)

    func testWindowKindsForModel() {
        XCTAssertEqual(HistoryFilter.windowKinds(for: .opus), ["seven_day_opus"])
        XCTAssertEqual(HistoryFilter.windowKinds(for: .sonnet), ["seven_day_sonnet"])
        XCTAssertEqual(HistoryFilter.windowKinds(for: .haiku), [])
        XCTAssertEqual(HistoryFilter.windowKinds(for: nil).count, UsageWindowKind.allCases.count)
    }

    func testFilterSamplesByTimeframe() {
        let now = Date(timeIntervalSince1970: 1000)
        let samples = [sample(100, [:]), sample(500, [:]), sample(950, [:])]
        let recent = HistoryFilter.samples(samples, span: 600, now: now)  // [400,1000]
        XCTAssertEqual(recent.count, 2)
    }
}
