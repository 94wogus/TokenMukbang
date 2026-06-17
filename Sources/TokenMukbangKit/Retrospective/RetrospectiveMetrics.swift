import Foundation

/// Usage-pattern metrics for a period — the structured signal the retrospective coach (B)
/// analyzes (ADR-0020, docs/VISION.md). The point of the retrospective is *coaching* ("how
/// to use tokens better"), not a description of what was done, so we feed `claude` these
/// derived patterns rather than a turn-count-biased dump of raw prompts.
///
/// Pure aggregation over `TokenEvent`s (+ per-project user-prompt counts) → lives in Kit and
/// is unit-tested (ADR-0001). Reuses `ModelCast`/`TokenHistory` conventions (ADR-0012).
public struct RetrospectiveMetrics: Sendable, Equatable {
    public struct Project: Sendable, Equatable {
        public let project: String
        public let consumed: Int        // input + output + cache-creation
        public let cacheRead: Int       // reheated context (proxy for context size)
        public let turns: Int           // assistant turns
        public let prompts: Int         // user prompts (steering)
        public let topModel: String     // dominant cast by tokens

        public init(project: String, consumed: Int, cacheRead: Int, turns: Int, prompts: Int, topModel: String) {
            self.project = project; self.consumed = consumed; self.cacheRead = cacheRead
            self.turns = turns; self.prompts = prompts; self.topModel = topModel
        }
        /// Tokens spent per user prompt — high ⇒ little steering (automation / long context).
        public var tokensPerPrompt: Int { prompts > 0 ? consumed / prompts : consumed }
        /// Cache-read tokens per turn — high ⇒ ballooned/long-running context.
        public var cachePerTurn: Int { turns > 0 ? cacheRead / turns : 0 }
    }

    public let projects: [Project]       // heaviest first
    public let totalConsumed: Int
    public let totalCacheRead: Int
    public let totalTurns: Int
    public let totalPrompts: Int
    public let opusShare: Double          // 0…1 of consumed tokens on Opus
    public let hourly: [Int]
    public let busiestHour: Int?
    public let baselineDeltaPercent: Double?

    public init(projects: [Project], totalConsumed: Int, totalCacheRead: Int, totalTurns: Int,
                totalPrompts: Int, opusShare: Double, hourly: [Int], busiestHour: Int?,
                baselineDeltaPercent: Double?) {
        self.projects = projects; self.totalConsumed = totalConsumed; self.totalCacheRead = totalCacheRead
        self.totalTurns = totalTurns; self.totalPrompts = totalPrompts; self.opusShare = opusShare
        self.hourly = hourly; self.busiestHour = busiestHour; self.baselineDeltaPercent = baselineDeltaPercent
    }

    /// Build metrics for `[periodStart, periodEnd)` from all token events + per-project user
    /// prompt counts (from `TranscriptDigest.collect`). Baseline = prior equal-length window.
    public static func build(events: [TokenEvent],
                             promptCounts: [String: Int],
                             periodStart: Date,
                             periodEnd: Date,
                             calendar: Calendar = TokenHistory.utcCalendar) -> RetrospectiveMetrics {
        let inPeriod = events.filter { $0.timestamp >= periodStart && $0.timestamp < periodEnd }

        // Group per project.
        var byProj: [String: [TokenEvent]] = [:]
        for e in inPeriod { byProj[e.project, default: []].append(e) }

        let projects: [Project] = byProj.map { project, evs in
            let consumed = evs.reduce(0) { $0 + $1.consumedTokens }
            let cacheRead = evs.reduce(0) { $0 + $1.cacheReadTokens }
            let topModel = TokenHistory.byCast(evs).first?.cast?.modelName ?? "Other"
            return Project(project: project, consumed: consumed, cacheRead: cacheRead,
                           turns: evs.count, prompts: promptCounts[project] ?? 0, topModel: topModel)
        }
        .filter { $0.consumed > 0 }
        .sorted { $0.consumed > $1.consumed }

        let total = projects.reduce(0) { $0 + $1.consumed }
        let cacheRead = projects.reduce(0) { $0 + $1.cacheRead }
        let turns = projects.reduce(0) { $0 + $1.turns }
        let prompts = projects.reduce(0) { $0 + $1.prompts }

        let opus = inPeriod.filter { $0.cast == .opus }.reduce(0) { $0 + $1.consumedTokens }
        let opusShare = total > 0 ? Double(opus) / Double(total) : 0

        var hourly = Array(repeating: 0, count: 24)
        for e in inPeriod {
            let h = calendar.component(.hour, from: e.timestamp)
            if h >= 0 && h < 24 { hourly[h] += e.consumedTokens }
        }
        let busiest: Int? = (hourly.max() ?? 0) > 0 ? hourly.firstIndex(of: hourly.max()!) : nil

        let span = periodEnd.timeIntervalSince(periodStart)
        let prevStart = periodStart.addingTimeInterval(-span)
        let prevActive = events
            .filter { $0.timestamp >= prevStart && $0.timestamp < periodStart }
            .reduce(0) { $0 + $1.consumedTokens }
        let delta = prevActive > 0 ? (Double(total - prevActive) / Double(prevActive)) * 100 : nil

        return RetrospectiveMetrics(
            projects: projects, totalConsumed: total, totalCacheRead: cacheRead, totalTurns: turns,
            totalPrompts: prompts, opusShare: opusShare, hourly: hourly, busiestHour: busiest,
            baselineDeltaPercent: delta)
    }

    /// The metrics rendered as compact text for the coach prompt — the pattern signal, not raw prompts.
    /// `planLabel` (e.g. "Max") lets the coach frame cost correctly: subscription plans burn the
    /// shared 5h/7d usage *window*, not dollars (ADR-0020 — plan-aware coaching).
    public func coachInputText(planLabel: String? = nil) -> String {
        func tk(_ n: Int) -> String { RetrospectiveSummary.tokens(n) }
        var lines: [String] = []
        if let plan = planLabel, !plan.isEmpty { lines.append("Plan: \(plan)") }
        var head = "Total \(tk(totalConsumed)) tokens · Opus \(Int((opusShare * 100).rounded()))%"
        if totalConsumed + totalCacheRead > 0 {
            let hit = Int((Double(totalCacheRead) / Double(totalConsumed + totalCacheRead) * 100).rounded())
            head += " · cache-read \(hit)%"
        }
        head += " · \(totalPrompts) user prompts over \(totalTurns) turns"
        if let h = busiestHour { head += " · busiest \(h):00 UTC" }
        if let d = baselineDeltaPercent { head += String(format: " · %@%.0f%% vs usual", d >= 0 ? "↑" : "↓", abs(d)) }
        lines.append(head)
        lines.append("")
        lines.append("Per project (tokens · user-prompts · tokens/prompt · cache-read/turn · model):")
        for p in projects.prefix(10) {
            lines.append("- \(p.project): \(tk(p.consumed)) · \(p.prompts)p · \(tk(p.tokensPerPrompt))/p · \(tk(p.cachePerTurn))/turn · \(p.topModel)")
        }
        return lines.joined(separator: "\n")
    }
}
