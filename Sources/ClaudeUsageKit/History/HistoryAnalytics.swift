import Foundation

/// Buckets history samples into a time series for sparklines / usage graphs.
public enum Sparkline {
    public struct Point: Sendable, Equatable {
        public let date: Date
        public let value: Double   // average utilization 0...100 in this bucket
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Average a window's utilization into `buckets` equal slots over the last
    /// `span` seconds. Empty buckets report 0.
    public static func series(
        from samples: [HistorySample],
        windowKind: String,
        span: TimeInterval,
        buckets: Int,
        now: Date
    ) -> [Point] {
        guard buckets > 0, span > 0 else { return [] }
        let start = now.addingTimeInterval(-span)
        let bucketSize = span / Double(buckets)
        var sums = Array(repeating: 0.0, count: buckets)
        var counts = Array(repeating: 0, count: buckets)

        for sample in samples {
            guard let u = sample.utilizations[windowKind] else { continue }
            let offset = sample.capturedAt.timeIntervalSince(start)
            guard offset >= 0, offset < span else { continue }
            let idx = min(buckets - 1, Int(offset / bucketSize))
            sums[idx] += u
            counts[idx] += 1
        }

        return (0..<buckets).map { i in
            let date = start.addingTimeInterval(bucketSize * (Double(i) + 0.5))
            let value = counts[i] > 0 ? sums[i] / Double(counts[i]) : 0
            return Point(date: date, value: value)
        }
    }
}

/// Filters history for the browser — by model cast (Opus/Sonnet/Haiku) and timeframe.
public enum HistoryFilter {
    /// Window kinds belonging to a model cast; nil cast → all windows.
    public static func windowKinds(for cast: ModelCast?) -> [String] {
        let all = UsageWindowKind.allCases.map(\.rawValue)
        guard let cast else { return all }
        return all.filter { ModelCast.forModel($0) == cast }
    }

    /// Keep only samples within [now - span, now].
    public static func samples(_ samples: [HistorySample], span: TimeInterval, now: Date) -> [HistorySample] {
        let start = now.addingTimeInterval(-span)
        return samples.filter { $0.capturedAt >= start && $0.capturedAt <= now }
    }
}
