import Foundation

extension RetrospectiveSummary {
    /// A plain-text rendering of the retrospective for copy-to-clipboard / sharing.
    /// English, mukbang voice (matches the UI). Includes the content layer (B) only
    /// when it's been generated. Pure formatting → lives in Kit and is unit-tested (ADR-0001).
    public var plainTextReport: String {
        var lines: [String] = []
        lines.append("TokenMukbang — Retrospective (\(Self.dateLabel(periodStart)))")

        var totalLine = "Total: \(Self.tokens(totalConsumed)) eaten"
        if let delta = baselineDeltaPercent {
            totalLine += String(format: " (%@%.0f%% vs usual)", delta >= 0 ? "↑" : "↓", abs(delta))
        }
        lines.append(totalLine)

        if !projects.isEmpty {
            lines.append("")
            lines.append("Menu (by project)")
            for p in projects.prefix(8) { lines.append("  \(p.project): \(Self.tokens(p.tokens))") }
        }
        if !casts.isEmpty {
            lines.append("")
            lines.append("Cast (by model)")
            for c in casts.prefix(8) { lines.append("  \(c.castName): \(Self.tokens(c.tokens))") }
        }
        if let peak = Self.peakHour(hourly) {
            lines.append("")
            lines.append("Busiest around \(peak):00 UTC")
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

    /// Index of the busiest UTC hour, or nil if there was no activity.
    public static func peakHour(_ hourly: [Int]) -> Int? {
        guard let maxV = hourly.max(), maxV > 0 else { return nil }
        return hourly.firstIndex(of: maxV)
    }

    public static func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}
