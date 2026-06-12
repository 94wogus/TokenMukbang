import Foundation

public enum Formatting {
    /// "2h 14m", "47m", "12s" — compact countdown until `date`.
    public static func countdown(to date: Date, from now: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "now" }
        let total = Int(remaining)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    /// "72%" from a 0...100 utilization.
    public static func percent(_ utilization: Double) -> String {
        "\(Int(utilization.rounded()))%"
    }

    /// "41%" from a 0...1 fraction.
    public static func percent(fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Compact token count: 1.2k / 3.4M / 1.9B.
    public static func tokenCount(_ n: Int) -> String {
        let d = Double(n)
        if n >= 1_000_000_000 { return String(format: "%.1fB", d / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fk", d / 1000) }
        return "\(n)"
    }

    /// A small unicode bar, e.g. ▓▓▓▓░ for ~72%.
    public static func bar(fraction: Double, width: Int = 5) -> String {
        let clamped = max(0, min(1, fraction))
        let filled = Int((Double(width) * clamped).rounded())
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
    }
}
