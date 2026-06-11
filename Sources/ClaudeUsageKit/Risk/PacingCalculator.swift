import Foundation

/// "Pacing vs equilibrium": where utilization *would* be if you consumed the
/// window evenly, versus where it actually is (TokenEater's Monitoring graph).
public enum PacingCalculator {
    /// The equilibrium line: expected utilization (%) for even consumption —
    /// i.e. the fraction of the window elapsed, as a percentage.
    public static func equilibrium(windowStart: Date, resetsAt: Date, now: Date) -> Double {
        let total = resetsAt.timeIntervalSince(windowStart)
        guard total > 0 else { return 0 }
        let elapsed = max(0, min(total, now.timeIntervalSince(windowStart)))
        return (elapsed / total) * 100.0
    }

    /// actual − equilibrium. Positive = ahead of pace (eating fast), negative = behind.
    public static func delta(utilization: Double, windowStart: Date, resetsAt: Date, now: Date) -> Double {
        utilization - equilibrium(windowStart: windowStart, resetsAt: resetsAt, now: now)
    }

    /// Whether the user is ahead of an even pace (burning faster than the clock).
    public static func isAheadOfPace(utilization: Double, windowStart: Date, resetsAt: Date, now: Date) -> Bool {
        delta(utilization: utilization, windowStart: windowStart, resetsAt: resetsAt, now: now) > 0
    }
}
