import Foundation

/// A single rate-limit window returned by `GET /api/oauth/usage`.
/// A window may be `null`, OR present with `utilization` but a **null `resets_at`** — the API
/// sends a null reset for a window with no scheduled reset yet (e.g. an unused window like
/// `seven_day_sonnet` at 0%). `resetsAt` is therefore optional so one null reset doesn't fail
/// the whole payload decode; windows without a reset are skipped downstream (`UsageService`).
public struct RateLimitWindow: Codable, Sendable, Equatable {
    /// Percentage 0...100 of this window consumed.
    public let utilization: Double
    /// When this window's allowance resets — `nil` if the API sent no reset (unused window).
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Logical identity of a usage window, kept stable for the UI regardless of how
/// many experimental buckets the API adds.
public enum UsageWindowKind: String, Sendable, CaseIterable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case sevenDayOpus = "seven_day_opus"
    case sevenDaySonnet = "seven_day_sonnet"

    /// Human label for menu-bar / widget rows.
    public var label: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .sevenDayOpus: return "Opus 7d"
        case .sevenDaySonnet: return "Sonnet 7d"
        }
    }

    /// How long this window spans — used to estimate when it opened
    /// (windowStart = resetsAt - duration) for pacing-aware risk (ADR: smart coloring).
    public var duration: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 60 * 60
        case .sevenDay, .sevenDayOpus, .sevenDaySonnet: return 7 * 24 * 60 * 60
        }
    }
}

/// Decoded `GET /api/oauth/usage` payload. The API exposes many nullable buckets;
/// we decode the four that drive v1 and keep the rest out of the model surface.
public struct Usage: Codable, Sendable, Equatable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?
    public let sevenDayOpus: RateLimitWindow?
    public let sevenDaySonnet: RateLimitWindow?

    public init(
        fiveHour: RateLimitWindow?,
        sevenDay: RateLimitWindow?,
        sevenDayOpus: RateLimitWindow?,
        sevenDaySonnet: RateLimitWindow?
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    /// Ordered, non-nil windows for display, primary (5h) first.
    public var displayWindows: [(kind: UsageWindowKind, window: RateLimitWindow)] {
        var out: [(UsageWindowKind, RateLimitWindow)] = []
        if let w = fiveHour { out.append((.fiveHour, w)) }
        if let w = sevenDay { out.append((.sevenDay, w)) }
        if let w = sevenDayOpus { out.append((.sevenDayOpus, w)) }
        if let w = sevenDaySonnet { out.append((.sevenDaySonnet, w)) }
        return out
    }
}
