import Foundation

/// A retrospective of a past period ("yesterday's you") — the reflection-mirror
/// product direction (ADR-0020, docs/VISION.md). Two layers:
///   • **A. metadata** (`projects`/`casts`/`hourly`/`baselineDeltaPercent`) — what you
///     spent tokens on and how, derived purely from local token counts (ADR-0011/0012).
///   • **B. content** (`topics`) — what you talked *about*, filled on demand by the
///     local `claude` CLI (ADR-0020). `nil` until the user explicitly generates it.
///
/// Codable + app-only: stored by `RetrospectiveStore` in Application Support and **never**
/// written into the widget-readable `SharedStore` snapshot (ADR-0003).
public struct RetrospectiveSummary: Codable, Sendable, Equatable {
    public let periodStart: Date
    public let periodEnd: Date

    /// Fresh tokens consumed in the period (input + output + cache-creation).
    public let totalConsumed: Int
    /// Per-project consumption, heaviest first.
    public let projects: [ProjectShare]
    /// Per-model-cast consumption, heaviest first ("출연진별 섭취량").
    public let casts: [CastShare]
    /// Tokens by UTC hour-of-day (24 buckets) — when you were eating.
    public let hourly: [Int]
    /// This period's active total vs the immediately preceding equal-length window.
    /// `nil` when there's no prior data to compare against.
    public let baselineDeltaPercent: Double?

    /// Content layer (B). `nil` until generated on demand via the `claude` CLI.
    public var topics: RetroTopics?

    public init(periodStart: Date, periodEnd: Date, totalConsumed: Int,
                projects: [ProjectShare], casts: [CastShare], hourly: [Int],
                baselineDeltaPercent: Double?, topics: RetroTopics? = nil) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.totalConsumed = totalConsumed
        self.projects = projects
        self.casts = casts
        self.hourly = hourly
        self.baselineDeltaPercent = baselineDeltaPercent
        self.topics = topics
    }

    public struct ProjectShare: Codable, Sendable, Equatable, Identifiable {
        public let project: String
        public let tokens: Int
        public var id: String { project }
        public init(project: String, tokens: Int) { self.project = project; self.tokens = tokens }
    }

    public struct CastShare: Codable, Sendable, Equatable, Identifiable {
        /// `ModelCast.modelName` (Opus/Sonnet/Haiku/Fable) or "Other" for the 기타 bucket.
        public let castName: String
        public let tokens: Int
        public var id: String { castName }
        public init(castName: String, tokens: Int) { self.castName = castName; self.tokens = tokens }
    }
}

/// The content layer (B) of a retrospective — "what you focused on" — produced by the
/// local `claude` CLI (ADR-0020). This is the one place app-derived *content* exists; it
/// stays app-only and never reaches the widget.
public struct RetroTopics: Codable, Sendable, Equatable {
    /// One-sentence "what you focused on" summary.
    public let summary: String
    /// Short list of themes/topics.
    public let themes: [String]
    public let generatedAt: Date
    public let source: Source

    public init(summary: String, themes: [String], generatedAt: Date, source: Source) {
        self.summary = summary
        self.themes = themes
        self.generatedAt = generatedAt
        self.source = source
    }

    public enum Source: String, Codable, Sendable {
        case claudeCLI   // analyzed by the local `claude` CLI
        case keyword     // B1 local-keyword fallback (no model)
    }
}
