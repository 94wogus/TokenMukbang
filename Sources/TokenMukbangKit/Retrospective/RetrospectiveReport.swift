import Foundation

extension RetrospectiveSummary {
    /// A plain-text rendering of the retrospective for copy-to-clipboard / sharing.
    /// English, mukbang voice (matches the UI). Includes the content layer (B) only
    /// when it's been generated. Pure formatting → lives in Kit and is unit-tested (ADR-0001).
    ///
    /// `timeZone` decides how the date + busiest-hour are *labelled* — defaults to UTC so tests
    /// stay deterministic; the app passes the user's display zone (`AppSettings.resolvedTimeZone`),
    /// matching the calendar that bucketed `hourly`.
    public func plainTextReport(timeZone: TimeZone = RetrospectiveSummary.utc) -> String {
        var lines: [String] = []
        lines.append("TokenMukbang — Retrospective (\(Self.dateLabel(periodStart, timeZone: timeZone)))")

        var totalLine = "Total: \(Self.tokens(totalConsumed)) eaten"
        if let delta = baselineDeltaPercent {
            totalLine += String(format: " (%@%.0f%% vs usual)", delta >= 0 ? "↑" : "↓", abs(delta))
        }
        lines.append(totalLine)

        if !projects.isEmpty {
            lines.append("")
            lines.append("Menu (by project)")
            // Same cap as the coach input so the report never hides a project the coach cites.
            for p in projects.prefix(RetrospectiveMetrics.maxListedProjects) { lines.append("  \(p.project): \(Self.tokens(p.tokens))") }
        }
        if !casts.isEmpty {
            lines.append("")
            lines.append("Cast (by model)")
            for c in casts.prefix(8) { lines.append("  \(c.castName): \(Self.tokens(c.tokens))") }
        }
        if let label = Self.busiestHourLabel(hourly, timeZone: timeZone) {
            lines.append("")
            lines.append("Busiest around \(label)")
        }
        if let topics {
            lines.append("")
            lines.append("How you're using it (coaching)")
            lines.append("TL;DR: " + topics.summary)
            for t in topics.themes { lines.append("  - \(t)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Compact token formatter (1.2M / 12.3k / 42) — shared by the report and mirrored by the UI.
    public static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Index of the busiest hour bucket, or nil if there was no activity. The bucket's zone is
    /// whichever calendar built `hourly` (UTC by default; the app's display zone live) — pair
    /// with `busiestHourLabel` for the zone-aware string.
    public static func peakHour(_ hourly: [Int]) -> Int? {
        guard let maxV = hourly.max(), maxV > 0 else { return nil }
        return hourly.firstIndex(of: maxV)
    }

    /// The busiest hour rendered in `timeZone` — "8:00 UTC" / "8:00 GMT+9" — or nil if idle.
    /// `hourly` must have been bucketed in the same zone (see `RetrospectiveBuilder`).
    public static func busiestHourLabel(_ hourly: [Int], timeZone: TimeZone) -> String? {
        guard let h = peakHour(hourly) else { return nil }
        return "\(h):00 \(zoneAbbrev(timeZone))"
    }

    /// Day label ("EEE, MMM d") in `timeZone`. Defaults to UTC for deterministic tests; the app
    /// passes the user's display zone so the date matches the zone the period was computed in.
    public static func dateLabel(_ date: Date, timeZone: TimeZone = RetrospectiveSummary.utc) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    /// Short zone label — "UTC" for the zero meridian, else the zone's abbreviation ("GMT+9")
    /// or, failing that, its identifier.
    static func zoneAbbrev(_ tz: TimeZone) -> String {
        if tz.identifier == "UTC" || tz.identifier == "GMT" { return "UTC" }
        return tz.abbreviation() ?? tz.identifier
    }

    /// UTC zone — the deterministic default for Kit formatting (tests/CLI). The app overrides it.
    public static let utc = TimeZone(identifier: "UTC")!
}
