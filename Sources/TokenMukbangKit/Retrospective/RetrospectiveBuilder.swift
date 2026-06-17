import Foundation

/// Builds the **metadata layer (A)** of a retrospective from local token events,
/// reusing `TokenHistory` aggregations (ADR-0011/0012) — no duplicated parsing.
///
/// Deliberately has **no `ProcessRunning`/summarizer dependency**: layer A can never
/// call the `claude` CLI, so the 60s poll (which only needs A for display) structurally
/// cannot spend tokens. The content layer (B) is a separate, explicit step
/// (`RetrospectiveSummarizing`) — the 먹방-paradox / on-demand invariant (ADR-0020).
public struct RetrospectiveBuilder: Sendable {
    public init() {}

    /// Build the A-layer summary for `[periodStart, periodEnd)` from `events`, comparing
    /// the period's active total against the immediately preceding equal-length window
    /// for a baseline delta ("vs 평소의 나").
    public func buildMetadata(events: [TokenEvent],
                              periodStart: Date,
                              periodEnd: Date,
                              calendar: Calendar = TokenHistory.utcCalendar) -> RetrospectiveSummary {
        let inPeriod = events.filter { $0.timestamp >= periodStart && $0.timestamp < periodEnd }

        let total = TokenHistory.total(inPeriod)

        let projects = TokenHistory.byProject(inPeriod)
            .map { RetrospectiveSummary.ProjectShare(project: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }

        let casts = TokenHistory.byCast(inPeriod)
            .map { RetrospectiveSummary.CastShare(castName: $0.cast?.modelName ?? "Other", tokens: $0.tokens) }

        var hourly = Array(repeating: 0, count: 24)
        for e in inPeriod {
            let hour = calendar.component(.hour, from: e.timestamp)
            if hour >= 0 && hour < 24 { hourly[hour] += e.consumedTokens }
        }

        let span = periodEnd.timeIntervalSince(periodStart)
        let prevStart = periodStart.addingTimeInterval(-span)
        let prevActive = events
            .filter { $0.timestamp >= prevStart && $0.timestamp < periodStart }
            .reduce(0) { $0 + $1.consumedTokens }
        let delta = prevActive > 0 ? (Double(total - prevActive) / Double(prevActive)) * 100 : nil

        return RetrospectiveSummary(
            periodStart: periodStart,
            periodEnd: periodEnd,
            totalConsumed: total,
            projects: projects,
            casts: casts,
            hourly: hourly,
            baselineDeltaPercent: delta,
            topics: nil
        )
    }

    /// Convenience: the A-layer summary for "yesterday" (the UTC day before `now`'s day).
    public func yesterday(events: [TokenEvent], now: Date,
                          calendar: Calendar = TokenHistory.utcCalendar) -> RetrospectiveSummary {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        return buildMetadata(events: events, periodStart: startOfYesterday,
                             periodEnd: startOfToday, calendar: calendar)
    }
}
