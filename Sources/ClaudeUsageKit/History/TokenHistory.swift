import Foundation

/// Aggregations over `TokenEvent`s — powers the History browser's bar charts,
/// heaviest-day and top-project callouts (TokenEater parity).
public enum TokenHistory {
    public struct DayBucket: Sendable, Equatable, Identifiable {
        public let day: Date          // start of day
        public let tokens: Int
        public var id: Date { day }
        public init(day: Date, tokens: Int) { self.day = day; self.tokens = tokens }
    }

    /// A UTC calendar so day bucketing is deterministic across machines/tests.
    public static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Total tokens per day, oldest first.
    public static func byDay(_ events: [TokenEvent], calendar: Calendar = TokenHistory.utcCalendar) -> [DayBucket] {
        var totals: [Date: Int] = [:]
        for e in events {
            let day = calendar.startOfDay(for: e.timestamp)
            totals[day, default: 0] += e.consumedTokens
        }
        return totals.map { DayBucket(day: $0.key, tokens: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Total tokens per model id.
    public static func byModel(_ events: [TokenEvent]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for e in events { totals[e.model, default: 0] += e.consumedTokens }
        return totals
    }

    /// One model cast's share of consumed tokens (nil cast = 기타: synthetic/unmapped).
    public struct CastTotal: Sendable, Equatable, Identifiable {
        public let cast: ModelCast?
        public let tokens: Int
        public var id: String { cast?.modelName ?? "기타" }
        public init(cast: ModelCast?, tokens: Int) { self.cast = cast; self.tokens = tokens }
    }

    /// Consumed tokens grouped by model cast (Opus/Sonnet/Haiku/Fable + nil "기타"),
    /// heaviest first. This is the per-model breakdown by *token volume* — note Opus
    /// dominates here because its turns carry far more tokens than Sonnet/Haiku turns
    /// even when those run more often (the API-utilization view tells a different story).
    public static func byCast(_ events: [TokenEvent]) -> [CastTotal] {
        var totals: [ModelCast?: Int] = [:]
        for e in events { totals[e.cast, default: 0] += e.consumedTokens }
        return totals.map { CastTotal(cast: $0.key, tokens: $0.value) }
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }

    /// One day's consumed tokens broken into per-model segments (for a stacked bar).
    public struct DayStack: Sendable, Equatable, Identifiable {
        public let day: Date
        public let segments: [CastTotal]   // canonical model order, only non-zero
        public var total: Int { segments.reduce(0) { $0 + $1.tokens } }
        public var id: Date { day }
        public init(day: Date, segments: [CastTotal]) { self.day = day; self.segments = segments }
    }

    /// Consumed tokens per day, each day split into model segments in a stable order
    /// (Opus→Sonnet→Haiku→Fable→기타) so the stacked bars line up across days.
    public static func byDayCast(_ events: [TokenEvent], calendar: Calendar = TokenHistory.utcCalendar) -> [DayStack] {
        let order: [ModelCast?] = ModelCast.allCases.map { Optional($0) } + [nil]
        var byDay: [Date: [ModelCast?: Int]] = [:]
        for e in events {
            let day = calendar.startOfDay(for: e.timestamp)
            byDay[day, default: [:]][e.cast, default: 0] += e.consumedTokens
        }
        return byDay.map { day, totals in
            let segs = order.compactMap { c -> CastTotal? in
                guard let t = totals[c], t > 0 else { return nil }
                return CastTotal(cast: c, tokens: t)
            }
            return DayStack(day: day, segments: segs)
        }
        .sorted { $0.day < $1.day }
    }

    /// Total tokens per project.
    public static func byProject(_ events: [TokenEvent]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for e in events { totals[e.project, default: 0] += e.consumedTokens }
        return totals
    }

    public static func total(_ events: [TokenEvent]) -> Int {
        events.reduce(0) { $0 + $1.consumedTokens }
    }

    /// The day with the most tokens consumed.
    public static func heaviestDay(_ events: [TokenEvent], calendar: Calendar = TokenHistory.utcCalendar) -> DayBucket? {
        byDay(events, calendar: calendar).max { $0.tokens < $1.tokens }
    }

    /// The project that consumed the most tokens.
    public static func topProject(_ events: [TokenEvent]) -> (project: String, tokens: Int)? {
        byProject(events).max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}
