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

/// Time ranges for the token History browser (TokenEater parity: 24h/7d/30d/90d).
public enum Timeframe: String, Sendable, CaseIterable, Identifiable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case quarter = "90d"

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var span: TimeInterval {
        switch self {
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        case .quarter: return 90 * 24 * 60 * 60
        }
    }
}

/// How the History browser breaks usage down by model. Two genuinely different metrics:
/// `tokens` = JSONL consumed-token volume (Opus-dominant); `utilization` = the OAuth API's
/// per-model limit % (where Sonnet shows meaningfully). The toggle exists because each
/// answers a different question ("who ate the most tokens?" vs "who's closest to a limit?").
public enum HistoryMetric: String, Sendable, CaseIterable, Identifiable {
    case tokens = "토큰량"
    case utilization = "사용률"
    public var id: String { rawValue }
    public var label: String { rawValue }
}

/// Filters history for the browser — by model cast (Opus/Sonnet/Haiku/Fable) and timeframe.
public enum HistoryFilter {
    /// Token events within a timeframe, optionally restricted to one model cast.
    public static func tokenEvents(
        _ events: [TokenEvent], timeframe: Timeframe, cast: ModelCast?, now: Date
    ) -> [TokenEvent] {
        let start = now.addingTimeInterval(-timeframe.span)
        return events.filter { e in
            e.timestamp >= start && e.timestamp <= now && (cast == nil || e.cast == cast)
        }
    }

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
