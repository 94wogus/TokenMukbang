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
            totals[day, default: 0] += e.totalTokens
        }
        return totals.map { DayBucket(day: $0.key, tokens: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Total tokens per model id.
    public static func byModel(_ events: [TokenEvent]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for e in events { totals[e.model, default: 0] += e.totalTokens }
        return totals
    }

    /// Total tokens per project.
    public static func byProject(_ events: [TokenEvent]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for e in events { totals[e.project, default: 0] += e.totalTokens }
        return totals
    }

    public static func total(_ events: [TokenEvent]) -> Int {
        events.reduce(0) { $0 + $1.totalTokens }
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
