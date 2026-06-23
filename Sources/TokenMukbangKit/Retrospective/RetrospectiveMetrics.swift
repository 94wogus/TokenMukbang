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
        public let consumed: Int        // "drain": output + fresh-input + cache-write — what burns the window
        public let output: Int          // output tokens — full price, biggest per-token cost
        public let freshInput: Int      // uncached input tokens
        public let cacheWrite: Int      // cache-creation tokens (re-cache after a >5-min idle gap)
        public let cacheRead: Int       // reheated context — near-free, does NOT drain the limit (context-size proxy only)
        public let turns: Int           // assistant turns
        public let prompts: Int         // user prompts (steering)
        public let topModel: String     // dominant cast by tokens

        public init(project: String, consumed: Int, output: Int, freshInput: Int, cacheWrite: Int,
                    cacheRead: Int, turns: Int, prompts: Int, topModel: String) {
            self.project = project; self.consumed = consumed; self.output = output
            self.freshInput = freshInput; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
            self.turns = turns; self.prompts = prompts; self.topModel = topModel
        }
        /// Tokens spent per user prompt — high ⇒ little steering (automation / long context).
        public var tokensPerPrompt: Int { prompts > 0 ? consumed / prompts : consumed }
        /// Cache-read tokens per turn — a context-size proxy ONLY. Cache reads are near-free
        /// and don't count toward the limit, so this is never foregrounded as a cost signal.
        public var cachePerTurn: Int { turns > 0 ? cacheRead / turns : 0 }
    }

    /// How many projects the coach prompt enumerates (heaviest first). The sample-prompt
    /// digest must be filtered to exactly these so the coach can't name an off-table project.
    public static let maxCoachedProjects = 10
    /// The heaviest projects shown to the coach (heaviest first), bounded by `maxCoachedProjects`.
    public var coachedProjects: [Project] { Array(projects.prefix(Self.maxCoachedProjects)) }

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
            let output = evs.reduce(0) { $0 + $1.outputTokens }
            let freshInput = evs.reduce(0) { $0 + $1.inputTokens }
            let cacheWrite = evs.reduce(0) { $0 + $1.cacheCreationTokens }
            let consumed = output + freshInput + cacheWrite     // == consumedTokens; the window-drain total
            let cacheRead = evs.reduce(0) { $0 + $1.cacheReadTokens }
            let topModel = TokenHistory.byCast(evs).first?.cast?.modelName ?? "Other"
            return Project(project: project, consumed: consumed, output: output, freshInput: freshInput,
                           cacheWrite: cacheWrite, cacheRead: cacheRead, turns: evs.count,
                           prompts: promptCounts[project] ?? 0, topModel: topModel)
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
    /// shared 5h/7d usage *window*, not dollars (ADR-0020 — plan-aware coaching). `timeZone` labels
    /// the busiest hour (defaults to UTC; the app passes the user's display zone, matching `hourly`).
    public func coachInputText(planLabel: String? = nil,
                               timeZone: TimeZone = RetrospectiveSummary.utc) -> String {
        func tk(_ n: Int) -> String { RetrospectiveSummary.tokens(n) }
        var lines: [String] = []
        if let plan = planLabel, !plan.isEmpty { lines.append("Plan: \(plan)") }
        var head = "Total \(tk(totalConsumed)) drain tokens · Opus \(Int((opusShare * 100).rounded()))%"
        head += " · \(totalPrompts) user prompts over \(totalTurns) turns"
        if let h = busiestHour { head += " · busiest \(h):00 \(RetrospectiveSummary.zoneAbbrev(timeZone))" }
        if let d = baselineDeltaPercent { head += String(format: " · %@%.0f%% vs usual", d >= 0 ? "↑" : "↓", abs(d)) }
        lines.append(head)
        // Tell the coach what the "drain" total means and that cache reads are NOT part of it —
        // the framing fix: cache reuse is near-free and does not count toward the 5h/7d limit.
        lines.append("(drain = output + fresh-input + cache-write — what burns the limit; cache reuse is near-free and excluded)")
        lines.append("")
        lines.append("Per project (drain · output · fresh-input · cache-write · user-prompts · tokens/prompt · model):")
        for p in coachedProjects {
            lines.append("- \(p.project): \(tk(p.consumed)) drain · \(tk(p.output)) out · \(tk(p.freshInput)) in · \(tk(p.cacheWrite)) cache-write · \(p.prompts)p · \(tk(p.tokensPerPrompt))/p · \(p.topModel)")
        }
        return lines.joined(separator: "\n")
    }
}
