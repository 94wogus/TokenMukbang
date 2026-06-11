import Foundation

/// Projects when a usage window will hit 100% ("완식") at the current pace.
/// Drives the "이 속도면 N시간 뒤 완식합니다" warning (ADR-0009 event line).
public enum PaceForecast {
    /// Whole hours until the window fills at the current burn rate, but only if
    /// it is on track to fill **before** it resets. Returns `nil` when:
    /// - already at/over 100% (the feast is done),
    /// - nothing consumed yet or the window hasn't opened (no rate),
    /// - or the projected fill time lands after the reset (safe pace).
    public static func hoursToFull(
        utilization: Double,
        windowStart: Date,
        resetsAt: Date,
        now: Date
    ) -> Int? {
        let used = utilization / 100.0
        guard used > 0, used < 1.0 else { return nil }

        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed > 0 else { return nil }

        // Burn rate in fraction-per-second; project the remaining fraction.
        let rate = used / elapsed
        guard rate > 0 else { return nil }
        let secondsToFull = (1.0 - used) / rate

        // Only warn if it fills before the window resets.
        let projectedFull = now.addingTimeInterval(secondsToFull)
        guard projectedFull < resetsAt else { return nil }

        return max(1, Int(ceil(secondsToFull / 3600.0)))
    }
}
