import Foundation

/// Aggregates Claude Code's telemetry metrics (ADR-0023 receiver → `TelemetryStore`) into the
/// human-facing activity figures the Now-tab card shows: edit-acceptance rate, lines of code
/// written, commits / PRs, and active time. Pure + dependency-free → fully unit-tested (ADR-0001).
///
/// **Why summing is correct.** Claude Code exports metrics with **delta** temporality by default
/// (`OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` defaults to `delta`, per the monitoring
/// docs), so each data point we store is the *increment* since the last export — summing all
/// points in the window gives the period total, with no double-counting and no per-series max.
public struct TelemetryDigest: Sendable, Equatable {
    public let linesAdded: Int
    public let linesRemoved: Int
    public let commits: Int
    public let pullRequests: Int
    public let editsAccepted: Int
    public let editsRejected: Int
    public let activeTimeSeconds: Double
    public let sessions: Int
    public let periodStart: Date
    public let periodEnd: Date

    public init(linesAdded: Int = 0, linesRemoved: Int = 0, commits: Int = 0, pullRequests: Int = 0,
                editsAccepted: Int = 0, editsRejected: Int = 0, activeTimeSeconds: Double = 0,
                sessions: Int = 0, periodStart: Date, periodEnd: Date) {
        self.linesAdded = linesAdded; self.linesRemoved = linesRemoved
        self.commits = commits; self.pullRequests = pullRequests
        self.editsAccepted = editsAccepted; self.editsRejected = editsRejected
        self.activeTimeSeconds = activeTimeSeconds; self.sessions = sessions
        self.periodStart = periodStart; self.periodEnd = periodEnd
    }

    /// Whether anything worth showing landed in the window — drives the card's empty/waiting state.
    public var hasData: Bool {
        linesAdded != 0 || linesRemoved != 0 || commits != 0 || pullRequests != 0
            || editsAccepted != 0 || editsRejected != 0 || activeTimeSeconds != 0 || sessions != 0
    }

    /// Fraction of edit-tool decisions the user accepted (0…1), or nil when there were none.
    public var acceptanceRate: Double? {
        let total = editsAccepted + editsRejected
        return total > 0 ? Double(editsAccepted) / Double(total) : nil
    }

    // The metric names + attribute values are the stable schema from Claude Code's
    // monitoring docs (verified 2026-06-30) — not guessed.
    enum Metric {
        static let linesOfCode = "claude_code.lines_of_code.count"
        static let commit = "claude_code.commit.count"
        static let pullRequest = "claude_code.pull_request.count"
        static let session = "claude_code.session.count"
        static let activeTime = "claude_code.active_time.total"
        static let editDecision = "claude_code.code_edit_tool.decision"
    }

    /// Sum the metric data points whose timestamp falls in `[periodStart, periodEnd)`.
    public static func build(metrics: [TelemetryMetricSample], periodStart: Date, periodEnd: Date) -> TelemetryDigest {
        var linesAdded = 0, linesRemoved = 0, commits = 0, prs = 0, accepted = 0, rejected = 0, sessions = 0
        var active = 0.0
        for m in metrics where m.timestamp >= periodStart && m.timestamp < periodEnd {
            let n = Int((m.value.doubleValue ?? 0).rounded())
            switch m.name {
            case Metric.linesOfCode:
                switch m.attributes["type"]?.stringValue {
                case "added": linesAdded += n
                case "removed": linesRemoved += n
                default: break
                }
            case Metric.commit: commits += n
            case Metric.pullRequest: prs += n
            case Metric.session: sessions += n
            case Metric.activeTime: active += m.value.doubleValue ?? 0
            case Metric.editDecision:
                switch m.attributes["decision"]?.stringValue {
                case "accept": accepted += n
                case "reject": rejected += n
                default: break
                }
            default: break
            }
        }
        return TelemetryDigest(
            linesAdded: linesAdded, linesRemoved: linesRemoved, commits: commits, pullRequests: prs,
            editsAccepted: accepted, editsRejected: rejected, activeTimeSeconds: active, sessions: sessions,
            periodStart: periodStart, periodEnd: periodEnd)
    }
}
