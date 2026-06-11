import Foundation

/// Continuous risk level for a usage window, combining absolute consumption with
/// pacing (how fast it is being spent relative to time left in the window).
public enum RiskLevel: String, Sendable, CaseIterable {
    case calm       // plenty of headroom
    case watch      // worth keeping an eye on
    case warning    // pacing toward the limit
    case critical   // at/near the cap

    /// Stable hex for UI; green → amber → orange → red.
    public var hex: String {
        switch self {
        case .calm: return "#34C759"
        case .watch: return "#FFD60A"
        case .warning: return "#FF9F0A"
        case .critical: return "#FF453A"
        }
    }

    public var label: String {
        switch self {
        case .calm: return "Calm"
        case .watch: return "Watch"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

public enum RiskScorer {
    /// Map a continuous 0...1 score to a discrete level.
    public static func level(forScore score: Double) -> RiskLevel {
        switch score {
        case ..<0.45: return .calm
        case ..<0.70: return .watch
        case ..<0.90: return .warning
        default: return .critical
        }
    }

    /// Risk score in 0...1 for a window.
    ///
    /// Blends absolute utilization with a pacing factor: if a large share of the
    /// window's allowance is already gone while a large share of its *time* still
    /// remains, the effective risk is pulled above raw utilization.
    ///
    /// - Parameters:
    ///   - utilization: 0...100 percent consumed.
    ///   - windowStart: when the current window opened (for pacing). Optional.
    ///   - resetsAt: when the window resets.
    ///   - now: current time.
    public static func score(
        utilization: Double,
        windowStart: Date? = nil,
        resetsAt: Date,
        now: Date
    ) -> Double {
        let used = max(0, min(1, utilization / 100.0))

        guard let start = windowStart, resetsAt > start else {
            return used
        }
        let total = resetsAt.timeIntervalSince(start)
        let elapsed = max(0, min(total, now.timeIntervalSince(start)))
        let timeFraction = total > 0 ? elapsed / total : 1.0

        // Pacing: usage-per-time-spent. >1 means burning faster than the clock.
        // Projected end-of-window utilization if the current pace holds.
        let projected: Double
        if timeFraction > 0.01 {
            projected = min(1.0, used / timeFraction)
        } else {
            projected = used
        }
        // Weight current usage more than the projection so early spikes don't
        // dominate, but let pacing raise the score.
        return max(used, 0.6 * used + 0.4 * projected)
    }

    public static func level(
        utilization: Double,
        windowStart: Date? = nil,
        resetsAt: Date,
        now: Date
    ) -> RiskLevel {
        level(forScore: score(utilization: utilization, windowStart: windowStart, resetsAt: resetsAt, now: now))
    }

    /// Discrete level from an absolute utilization % using the user's custom
    /// warning/critical thresholds (Settings, ADR: customizable thresholds).
    public static func level(percent: Double, thresholds: RiskThresholds) -> RiskLevel {
        if percent >= thresholds.critical { return .critical }
        if percent >= thresholds.warning { return .warning }
        if percent >= thresholds.warning * 0.6 { return .watch }
        return .calm
    }
}
